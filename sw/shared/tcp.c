////////////////////////////////////////////////////////////////////////////
//                                                                        //
// tcp.c                                                                  //
//                                                                        //
// TCP                                                                    //
//                                                                        //
// See comments and commentary in network.h                               //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "intercore.h"
#include "network.h"

#define stateSynSent 1
#define stateSynReceived 2
#define stateEstablished 3
#define stateFinWait1 4
#define stateFinWait2 5
#define stateCloseWait 6
#define stateClosing 7
#define stateLastAck 8
#define stateTimeWait 9
#define stateTimeWaitClosed 10
// stateTimeWaitClosed tells the retransmitter thread to eventually
// dispose of the tcp structure, because the client has already
// called tcp_close.
#define stateClosed 11

#define flagFin 1
#define flagSyn 2
#define flagReset 4
#define flagPush 8
#define flagAck 16
#define flagUrgent 32

typedef struct TCPHeader {
  Uint16 srce;
  Uint16 dest;
  Uint32 seq;
  Uint32 ack;
  Uint16 misc;
  Uint16 window;
  Uint16 checksum;
  Uint16 urgent;
  // Followed by options (if any), then data.
} TCPHeader;

typedef struct MSSOption {
  Octet mssKind;          // Option-kind = 2, MSS
  Octet mssLen;           // Option-length = 4;
  Uint16 mss;             // Maximum receive segment size.
} MSSOption;

#define maxRecvWindow 8000

typedef struct TransmitElem { // (re)transmission queue element
  IP *buf;
  Uint32 len;             // TCP payload bytes currently in buf
  Uint32 seq;             // sequence number of first byte in buf
  Uint16 flag;            // extra flag for transmission (PUSH or FIN)
  Microsecs sentAt;       // time at which buf was last transmitted
  Microsecs firstSentAt;  // time at which buf was first transmitted
  struct TransmitElem *next;
} TransmitElem;

struct TCP {              // Connection state block
  TCPPort localPort;
  IPAddr remoteAddr;
  TCPPort remotePort;
  int state;              // the overall state machine
  int failed;             // set iff closed by timeout, RESET, or tcp_abort
  Uint32 sendNext;        // sequence number of next byte for transmit queue
  Uint32 sendInit;        // sequence number of our initial SYN
  Uint32 sendUnack;       // sequence number of first unacknowledged byte
  Uint32 sendWindow;      // relative to sendUnack
  Uint32 sendNagled;      // bool: transmission was blocked by Nagle
  Uint32 transmitted;     // sequence number of next byte to be transmitted
  Uint32 recvNext;        // sequence number of next byte to be received
  Uint32 recvInit;        // initial recv sequence number
  Uint32 recvWindow;      // byte count relative to recvNext
  TransmitElem *transmitHead; // retransmission queue
  TransmitElem *transmitTail; // current, untransmitted, send buffer
  Octet *recvBuf;         // cyclic queue of data not yet consumed by client
  int recvBufStart;       // start of data in recvBuf
  int recvBufCount;       // amount of data in recvBuf
  int recvPushed;         // last received byte had the PUSH flag set
  IP *outOfOrderHead;     // head of ouot-of-order packet queue
  IP *outOfOrderTail;     // tail of out-of-order packet queue
  TCP nextPending;        // list of not-yet-accepted connections
  TCP nextActive;         // list of connections for localPort
};

typedef struct Listener {
  IPAddr remoteAddr;
  TCPPort remotePort;
  int backlog;            // limit on length of pending
  TCP pending;            // queue of established but not accepted
  TCP pendingTail;
  int pendingCount;       // length of pending
} * Listener;

static Mutex tcpMutex = NULL;
static Condition tcpAcceptCond = NULL;
static Condition tcpConnectCond = NULL;
static Condition tcpRecvCond = NULL;
static Condition tcpCloseCond = NULL;
static Condition tcpCreateCond = NULL;
static Condition tcpSendCond = NULL;
static IP *tcpSmallBuf = NULL;   // for transmitting SYN, ACK, RST, etc.
static TCP tcpActive;            // active connection list
static Listener *tcpListeners;   // listening state; NULL if not in use
static unsigned int tcpSeed;     // state for various random numbers

static Uint32 tcpHeaderSize(IP *buf) {
  return (ntohs(((TCPHeader *)ip_payload(buf))->misc) >> 12) << 2;
}

static Octet * tcpPayload(IP *buf) {
  return ip_payload(buf) + tcpHeaderSize(buf);
}

static int seqComp(Uint32 a, Uint32 b) {
  // Compare sequence numbers, with appropriate wrapping at 2^32,
  // i.e., such that seqComp(1, 2^32-1) == 1.
  //
  // Return (-1, 0, 1) if a ( before, =, after ) b.
  //
  int diff = (int)a - (int)b;
  return (diff > 0 ? 1 : (diff < 0 ? -1 : 0));
}

Uint16 payloadChecksum(IP *buf, Uint32 len);
static void tcpInit();

static void tcpSend(TCP tcp, IP *buf, Uint32 len, Uint32 bufSeq,
		    Uint16 flags) {
  // Transmit the buffer as a TCP packet.
  // "len" is TCP payload length.
  // Assumes tcpMutex is held
  buf->ip.dest = hton(tcp->remoteAddr);
  buf->ip.protocol = ipProtocolTCP;
  buf->ip.versionAndLen = 0x45; // IPv4, 5 words in header
  ip_setSrce(buf);
  TCPHeader *tcpHeader = (TCPHeader *)ip_payload(buf);
  int hSize = sizeof(TCPHeader);
  if ((flags & flagSyn) && len == 0) {
    MSSOption *mssOption =
      (MSSOption *)(ip_payload(buf) + sizeof(TCPHeader));
    mssOption->mssKind = 2;
    mssOption->mssLen = 4;
    mssOption->mss = htons(ipPayloadSize - sizeof(TCPHeader));
    hSize += sizeof(MSSOption);
  }
  tcpHeader->srce = htons(tcp->localPort);
  tcpHeader->dest = htons(tcp->remotePort);
  tcpHeader->seq = hton(bufSeq);
  tcpHeader->ack = hton(tcp->recvNext);
  tcpHeader->misc = htons(flags | ((hSize >> 2) << 12));
  tcpHeader->window = htons(tcp->recvWindow);
  tcpHeader->checksum = 0;
  tcpHeader->checksum = payloadChecksum((IP *)buf,
					len + tcpHeaderSize(buf));
  ip_send(buf, len + tcpHeaderSize(buf), 0, 0);
}

static void sendSmall(TCP tcp, Uint32 seq, Uint16 flags) {
  // Send a SYN and/or ACK using tcpSmallBuf
  // Assumes tcpMutex is held
  tcpSend(tcp, tcpSmallBuf, 0, seq, flags);
}

static TCP createTcp(TCPPort localPort, IPAddr remoteAddr,
			    TCPPort remotePort) {
  // Create a connection control block.
  // Assumes tcpMutex is held.
  // Defers allocation of tcp->recvBuf until we receive some data.
  //
  TCP tcp = malloc(sizeof(struct TCP));
  tcp->localPort = localPort;
  tcp->remoteAddr = remoteAddr;
  tcp->remotePort = remotePort;
  tcp->state = stateClosed;
  tcp->failed = 0;
  tcp->sendInit = rand_r(&tcpSeed);
  tcp->sendNext = tcp->sendInit;
  tcp->sendUnack = tcp->sendNext;
  tcp->sendWindow = 0;
  tcp->sendNagled = 0;
  tcp->transmitted = tcp->sendNext;
  tcp->recvInit = 0;
  tcp->recvNext = 0;
  tcp->recvWindow = maxRecvWindow;
  tcp->transmitHead = tcp->transmitTail = NULL;
  tcp->recvBuf = NULL;
  tcp->recvBufStart = 0;
  tcp->recvBufCount = 0;
  tcp->recvPushed = 0;
  tcp->outOfOrderHead = tcp->outOfOrderTail = NULL;
  tcp->nextPending = NULL;
  if (!tcpActive) condition_broadcast(tcpCreateCond);
  tcp->nextActive = tcpActive;
  tcpActive = tcp;
  return tcp;
}

static void deleteTcp(TCP tcp) {
  // Remove tcb from the active list, and free it
  // Assumes tcpMutex is locked
  TCP prev = NULL;
  TCP this;
  for (this = tcpActive; this != NULL; this = this->nextActive) {
    if (this == tcp) {
      if (prev) {
	prev->nextActive = this->nextActive;
      } else {
	tcpActive = this->nextActive;
      }
      break;
    } else {
      prev = this;
    }
  }
  if (this) {
    TransmitElem *elem = this->transmitHead;
    while (elem) {
      TransmitElem *next = elem->next;
      enet_free((Enet *)elem->buf);
      free(elem);
      elem = next;
    }
    this->transmitHead = NULL;
    if (this->recvBuf) free(this->recvBuf);
    IP *oooBuf = this->outOfOrderHead;
    while (oooBuf) {
      IP *next = oooBuf->next;
      enet_free((Enet *)oooBuf);
      oooBuf = next;
    }
    free(this);
  }
}

static TCP findTcp(TCPPort localPort, IPAddr remoteAddr,
		   TCPPort remotePort) {
  // Find existing connection, if any.
  // Assumes tcpMutex is held.
  // TEMP: a hash table would be a good idea.
  TCP tcp;
  for (tcp = tcpActive; tcp != NULL; tcp = tcp->nextActive) {
    if (tcp->localPort == localPort &&
	tcp->remoteAddr == remoteAddr &&
	tcp->remotePort == remotePort) break;
  }
  return tcp;
}

static void appendTransmitElem(TCP tcp) {
  // Append an element to our transmission queue.
  // Assumes tcpMutex is held.
  TransmitElem *elem = malloc(sizeof(TransmitElem));
  elem->buf = (IP *)enet_alloc();
  elem->len = 0;
  elem->seq = tcp->sendNext;
  elem->flag = 0;
  elem->sentAt = 0;
  elem->next = NULL;
  if (tcp->transmitHead) {
    tcp->transmitTail->next = elem;
  } else {
    tcp->transmitHead = elem;
  }
  tcp->transmitTail = elem;
}

static void pruneTransmitQueue(TCP tcp) {
  // Remove acknowledged data from the transmission queue.
  // Assumes tcpMutex is held.
  Uint32 ack = tcp->sendUnack;
  while (tcp->transmitHead != tcp->transmitTail) {
    TransmitElem *elem = tcp->transmitHead;
    Uint32 contents = elem->len + (elem->flag == flagFin ? 1 : 0);
    if (seqComp(ack, elem->seq + contents) < 0) break;
    tcp->transmitHead = elem->next;
    enet_free((Enet *)elem->buf);
    free(elem);
  }
}

void tcp_listen(TCPPort localPort, IPAddr remoteAddr, TCPPort remotePort,
		int backlog) {
  tcpInit();
  mutex_acquire(tcpMutex);
  Listener listener;
  TCP abandoned = NULL; // Queue of abandoned connections
  if (!(listener = tcpListeners[localPort])) {
    listener = tcpListeners[localPort] = malloc(sizeof(struct Listener));
    listener->pending = NULL;
    listener->pendingTail = NULL;
    listener->pendingCount = 0;
  }
  listener->remoteAddr = remoteAddr;
  listener->remotePort = remotePort;
  listener->backlog = backlog;
  if (backlog < 0) {
    abandoned = listener->pending;
    free(listener);
    tcpListeners[localPort] = NULL;
  }
  mutex_release(tcpMutex);
  while (abandoned != NULL) {
    TCP tcp = abandoned;
    abandoned = abandoned->nextPending;
    tcp_abort(tcp);
    tcp_close(tcp);
  }
}

TCP tcp_accept(TCPPort localPort, IPAddr *remoteAddr, TCPPort *remotePort,
	       Microsecs microsecs) {
  tcpInit();
  TCP tcp = NULL;
  mutex_acquire(tcpMutex);
  while (!tcp) {
    Listener listener;
    while ((listener = tcpListeners[localPort]) &&
	   (!listener->pending ||
	    listener->pending->state == stateSynReceived)) {
      if (condition_timedWait(tcpAcceptCond, tcpMutex, microsecs)) {
	listener = NULL;
	break;
      }
    }
    if (!listener) break;
    tcp = listener->pending;
    listener->pending = tcp->nextPending;
    if (tcp == listener->pendingTail) listener->pendingTail = NULL;
    if (tcp->state == stateClosed) {
      deleteTcp(tcp);
      tcp = NULL;
    }
  }
  if (tcp) {
    if (remoteAddr) *remoteAddr = tcp->remoteAddr;
    if (remotePort) *remotePort = tcp->remotePort;
  }
  mutex_release(tcpMutex);
  return tcp;
}

TCP tcp_connect(TCPPort localPort, IPAddr remoteAddr, TCPPort remotePort,
		Microsecs microsecs) {
  tcpInit();
  if (remoteAddr == 0 || remotePort == 0) return NULL;
  // TEMP: should also reject broadcast and multicast addresses
  mutex_acquire(tcpMutex);
  if (localPort == 0) {
    for (;;) {
      localPort = rand_r(&tcpSeed) & 65535;
      if (localPort > 1024 &&
	  !findTcp(localPort, remoteAddr, remotePort)) break;
    }
  }
  TCP tcp = createTcp(localPort, remoteAddr, remotePort);
  sendSmall(tcp, tcp->sendNext, flagSyn);
  tcp->sendNext++;
  tcp->transmitted = tcp->sendNext;
  tcp->state = stateSynSent;
  appendTransmitElem(tcp);
  while (tcp->state == stateSynSent || tcp->state == stateSynReceived) {
    if (condition_timedWait(tcpConnectCond, tcpMutex, microsecs)) {
      tcp->state = stateClosed;
    }
  }
  if (tcp->state == stateClosed) {
    deleteTcp(tcp);
    tcp = NULL;
  }
  mutex_release(tcpMutex);
  // Note that we never return in stateSynSent or stateSynReceived.
  return tcp;
}

static void transmitElemNow(TCP tcp, TransmitElem *elem) {
  // Transmit given buffer now.
  tcpSend(tcp, elem->buf, elem->len, elem->seq, flagAck | elem->flag);
  elem->sentAt = thread_now();
}

static void abortInner(TCP tcp) {
  // Same as tcp_abort, but with tcpMutex held
  switch (tcp->state) {
  case stateSynReceived:
  case stateEstablished:
  case stateFinWait1:
  case stateFinWait2:
  case stateCloseWait:
    sendSmall(tcp, tcp->transmitted, flagReset + flagAck);
    break;
  }
  tcp->state = stateClosed;
  tcp->failed = 1;
  condition_signal(tcpAcceptCond);
  condition_broadcast(tcpSendCond);
  condition_broadcast(tcpRecvCond);
  condition_broadcast(tcpCloseCond);
}

static void retransmitter(void *arg) {
  // Our retransmission thread.  The transmitted packets are listed
  // starting at transmitHead; transmitTail has not been transmitted;
  // both are always valid any time we can see them.
  //
  // TEMP: we make no attempt at sensible timing decisions
  //
  mutex_acquire(tcpMutex);
  for (;;) {
    while (!tcpActive) condition_wait(tcpCreateCond, tcpMutex);
    condition_timedWait(tcpCreateCond, tcpMutex, 2000000);
    for (TCP tcp = tcpActive; tcp != NULL; tcp = tcp->nextActive) {
      switch (tcp->state) {
      case stateSynSent:
	sendSmall(tcp, tcp->sendInit, flagSyn);
	break;
      case stateSynReceived:
	sendSmall(tcp, tcp->sendInit, flagSyn | flagAck);
	break;
      case stateClosed:
	break;
      default: {
	  TransmitElem *elem = tcp->transmitHead;
	  if (elem != tcp->transmitTail) {
	    if (elem->sentAt - elem->firstSentAt > 20 * 1000 * 1000) {
	      abortInner(tcp);
	      break; // from loop
	    }
	    transmitElemNow(tcp, elem);
	  }
	  break;
	}
      }
    }
  }
  mutex_release(tcpMutex);
}

static void sendData(TCP tcp) {
  // Transmit tcp->transmitTail, advance tcp->transmitted, and append
  // a new transmitElem.  Assumes tcpMutex is held
  //
  TransmitElem *elem = tcp->transmitTail;
  transmitElemNow(tcp, elem);
  elem->firstSentAt = elem->sentAt;
  tcp->transmitted = elem->seq + elem->len;
  if (elem->flag == flagFin) tcp->transmitted++;
  tcp->sendNagled = 0;
  appendTransmitElem(tcp);
}

int tcp_send(TCP tcp, Octet *buf, Uint32 len) {
  // Aggregate data into transmission buffers, transmitting any full ones.
  // Because this function only transmits full buffers, Nagle doesn't apply.
  //
  // We yield once per packet, so we don't ignore acks.
  //
  if (len < 0) len = 0;
  int sent = 0;
  while (len > 0) {
    mutex_acquire(tcpMutex);
    switch (tcp->state) {
    case stateEstablished:
    case stateCloseWait: {
      TransmitElem *elem = tcp->transmitTail;
      Uint32 offset = sizeof(TCPHeader) + elem->len;
      Uint32 amount = ipPayloadSize - offset;
      if (amount == 0) {
	sendData(tcp);
      } else {
	if (amount > len) amount = len;
	Uint32 limit = elem->seq + elem->len + amount;
	if (seqComp(limit, tcp->sendUnack + tcp->sendWindow) > 0) {
	  printf("Send blocked at %d for %d\n",
		 tcp->sendUnack + tcp->sendWindow - tcp->sendInit,
		 limit - tcp->sendInit);
	  // TEMP: we need to do zero-window probing
	  condition_wait(tcpSendCond, tcpMutex);
	} else {
	  bcopy(buf, (Octet *)&(elem->buf->data) + offset, amount);
	  len -= amount;
	  buf += amount;
	  elem->len += amount;
	  elem->sentAt = 0;
	  tcp->sendNext += amount;
	  sent += amount;
	}
      }
      break;
    }
    default:
      sent = tcpConnectionDied;
      break;
    }
    mutex_release(tcpMutex);
    if (len > 0) thread_yield();
  }
  return sent;
}

void tcp_push(TCP tcp) {
  // Force transmission of aggregated data in a partial packet, unless
  // prohibited by Nagle's algorithm.  If there's no aggregated data
  // we'll send an empty buffer to communicate the PUSH, subject to Nagle.
  mutex_acquire(tcpMutex);
  switch (tcp->state) {
  case stateEstablished:
  case stateCloseWait:
    tcp->transmitTail->flag = flagPush;
    if (tcp->sendUnack != tcp->transmitted) {
      tcp->sendNagled = 1;
    } else {
      sendData(tcp);
    }
    break;
  }
  mutex_release(tcpMutex);
}

void tcp_shutdown(TCP tcp) {
  // Send FIN on our outbound stream, if legal; else ignore
  mutex_acquire(tcpMutex);
  switch (tcp->state) {
  case stateEstablished:
  case stateCloseWait:
    tcp->sendNext++; // sequence number consumed by the FIN
    tcp->transmitTail->flag = flagFin;
    sendData(tcp);
    tcp->state = (tcp->state == stateCloseWait ? stateLastAck :
		  stateFinWait1);
    break;
  }
  mutex_release(tcpMutex);
}

int tcp_recv(TCP tcp, Octet *buf, Uint32 len) {
  // We deliver data if it's there, regardless of the state
  int recvd = 0;
  mutex_acquire(tcpMutex);
  while (len > 0) {
    int amount = len;
    if (amount > tcp->recvBufCount) amount = tcp->recvBufCount;
    if (amount == 0) {
      if (tcp->recvPushed) break;
      switch (tcp->state) {
      case stateCloseWait:
      case stateClosing:
      case stateLastAck:
      case stateTimeWait:
      case stateTimeWaitClosed:
      case stateClosed:
	len = 0; // force eventual exit from loop
	if (tcp->failed) recvd = tcpConnectionDied;
	break;
      default:
	condition_wait(tcpRecvCond, tcpMutex);
	break; // from switch, not loop
      }
    } else {
      if (tcp->recvBufStart + amount > maxRecvWindow) {
	amount = maxRecvWindow - tcp->recvBufStart;
      }
      bcopy(tcp->recvBuf + tcp->recvBufStart, buf, amount);
      tcp->recvBufStart += amount;
      if (tcp->recvBufStart == maxRecvWindow) tcp->recvBufStart = 0;
      tcp->recvBufCount -= amount;
      buf += amount;
      len -= amount;
      recvd += amount;
      if (tcp->recvWindow < 1460 &&
	  maxRecvWindow - tcp->recvBufCount >= 1460) {
	// update the other end's transmit window if it was too small
	tcp->recvWindow = maxRecvWindow - tcp->recvBufCount;
	sendSmall(tcp, tcp->transmitted, flagAck);
      }
    }
  }
  if (tcp->recvBufCount == 0) tcp->recvPushed = 0;
  mutex_release(tcpMutex);
  return recvd;
}

void tcp_abort(TCP tcp) {
  // Sends a reset unless we've sent and received FIN,
  // with the exception of stateSynSent, which we just abandon.
  mutex_acquire(tcpMutex);
  abortInner(tcp);
  mutex_release(tcpMutex);
}

void tcp_close(TCP tcp) {
  // Client is done with tcp.
  //
  // Note that this isn't "close" in the RFC; we follow BSD socket
  // terminology and call that "shutdown".
  //
  tcp_shutdown(tcp); // sends our FIN iff established or closeWait
  mutex_acquire(tcpMutex);
  // Wait for ack of our FIN, if we've sent one.
  while (tcp->state == stateFinWait1 ||
	 tcp->state == stateClosing ||
	 tcp->state == stateLastAck) {
    condition_wait(tcpCloseCond, tcpMutex);
  }
  switch (tcp->state) {
  case stateSynReceived:
  case stateFinWait2:
    // We're done, but haven't had a FIN from the other end, so reset.
    // Note that the client has promised to do no more tcp_recv's on this
    // stream, so we'll necessarily discard anything else from the sender,
    // so a reset is appropriate.
    sendSmall(tcp, tcp->transmitted, flagReset + flagAck);
    tcp->state = stateClosed;
    tcp->failed = 1;
    deleteTcp(tcp);
    break;
  case stateTimeWait:
    // The TCP is still needed, to respond to retransmissions of the other
    // end's FIN.  The retransmitter thread will eventually call deleteTcp.
    // TEMP: no it doesn't.
    tcp->state = stateTimeWaitClosed;
    break;
  case stateTimeWaitClosed:
    // Client error.
    break;
  case stateSynSent:
  case stateClosed:
    tcp->state = stateClosed;
    deleteTcp(tcp);
    break;
  }
  mutex_release(tcpMutex);
}

static void tcpRejectUnknown(IP *buf) {
  // Reject a TCP packet for an unknown or closed connection.
  // Assumes tcpMutex is held, and the packet is otherwise valid.
  //
  TCPHeader *tcpHeader = (TCPHeader *)ip_payload(buf);
  TCPPort localPort = ntohs(tcpHeader->dest);
  IPAddr remoteAddr = ntoh(buf->ip.srce);
  TCPPort remotePort = ntohs(tcpHeader->srce);
  int flags = ntohs(tcpHeader->misc);
  Uint32 payloadLen = ip_payloadSize(buf) - tcpHeaderSize(buf);
  if (!(flags & flagReset)) {
    TCP tcp = createTcp(localPort, remoteAddr, remotePort);
    if (flags & flagAck) {
      sendSmall(tcp, ntoh(tcpHeader->ack), flagReset);
    } else {
      tcp->recvNext = ntoh(tcpHeader->seq) + payloadLen;
      sendSmall(tcp, 0, flagReset | flagAck);
    }
    deleteTcp(tcp);
  }
}

static int tcpProcessData(TCP tcp, IP *buf) {
  // Process data content and FIN, if relevant.
  // Assumes tcpMutex is held, and tcp->state is appropriate for receiving
  // data or FIN.
  //
  // Returns true iff entire packet has been consumed.
  //
  TCPHeader *tcpHeader = (TCPHeader *)ip_payload(buf);
  int flags = ntohs(tcpHeader->misc);
  Uint32 seq = ntoh(tcpHeader->seq);
  Uint32 payloadLen = ip_payloadSize(buf) - tcpHeaderSize(buf);
  if (flags & flagSyn) seq++;
  if (seqComp(seq, tcp->recvNext) <= 0) {
    int base = tcp->recvNext - seq; // first useful byte
    int amount = payloadLen - base; // number of useful bytes
    if (tcp->recvBufCount + amount > maxRecvWindow) {
      // Don't overflow recvBuf
      amount = maxRecvWindow - tcp->recvBufCount;
    }
    if (amount > 0) {
      // Copy the bytes, wrapping at end of recvBuf
      if (!tcp->recvBuf) tcp->recvBuf = malloc(maxRecvWindow);
      int dest1 = tcp->recvBufStart + tcp->recvBufCount;
      if (dest1 >= maxRecvWindow) dest1 -= maxRecvWindow;
      int part1 = amount;
      if (dest1 + part1 > maxRecvWindow) {
	part1 = maxRecvWindow - dest1;
      }
      Octet *data = tcpPayload(buf) + base;
      bcopy(data, tcp->recvBuf + dest1, part1);
      if (part1 < amount) {
	bcopy(data + part1, tcp->recvBuf, amount - part1);
      }
      tcp->recvBufCount += amount;
      tcp->recvNext += amount;
      tcp->recvWindow = maxRecvWindow - tcp->recvBufCount;
    }
    if ((flags & flagPush) && amount == payloadLen - base) {
      // PUSH and we accepted the last byte
      tcp->recvPushed = 1;
    } else {
      tcp->recvPushed = 0;
    }
    condition_broadcast(tcpRecvCond);
  }
  seq += payloadLen;
  if (flags & flagFin) {
    if (seq == tcp->recvNext) { // if we consumed all the data bytes
      if (tcp->state == stateEstablished) {
	tcp->state = stateCloseWait;
      } else if (tcp->state == stateFinWait1) {
	tcp->state = stateClosing;
      } else if (tcp->state == stateFinWait2) {
	tcp->state = stateTimeWait;
      } // else ignore it
      tcp->recvNext++;
      condition_broadcast(tcpRecvCond);
    }
    seq++;
  }
  // "seq" is now 1 beyond end of packet (and of its FIN, if any)
  return seqComp(seq, tcp->recvNext) <= 0;
}

static int tcpProcessIncoming(TCP tcp, IP *buf) {
  // Process incoming packet for this connection.
  //
  // Assumes tcpMutex is held, and buf is a valid TCP packet for this
  // connection, and connection isn't closed.  Queues out-of-order packets.
  //
  // Returns true iff we should be sending an ACK about now.
  //
  TCPHeader *tcpHeader = (TCPHeader *)ip_payload(buf);
  int flags = ntohs(tcpHeader->misc);
  Uint32 seq = ntoh(tcpHeader->seq);
  Uint32 ack = ntoh(tcpHeader->ack);
  Uint32 payloadLen = ip_payloadSize(buf) - tcpHeaderSize(buf);
  int shouldAck = (payloadLen > 0 || flags & flagSyn || flags & flagFin);

  if (tcp && (flags & flagAck)) {
    // Update our transmission state according to acknowledged seq.
    //
    if (seqComp(tcp->sendUnack, ack) <= 0 &&
	seqComp(ack, tcp->transmitted) <= 0) {
      tcp->sendUnack = ack;
      pruneTransmitQueue(tcp);
    } else if (tcp->state == stateSynSent ||
	       tcp->state == stateSynReceived) {
      // Unacceptable ack while not yet synchronized: reset and ignore
      printf("TCP unacceptable ACK before established\n");
      if (!(flags & flagReset)) {
	sendSmall(tcp, ntoh(tcpHeader->ack), flagReset);
      }
      tcp = NULL;
    } else {
      // Ancient data, garbage, or null ack (keep-alive or window probe)
      shouldAck = 1;
    }
  }

  if (tcp && (flags & flagReset)) {
    // Connection rejected/abandoned by other end
    //
    tcp->state = stateClosed;
    tcp->failed = 1;
    condition_signal(tcpAcceptCond);
    condition_broadcast(tcpConnectCond);
    condition_broadcast(tcpSendCond);
    condition_broadcast(tcpRecvCond);
    // If we're established (or later), the client will eventually call
    // deleteTcp.  If we're being created by tcp_connect (active open in the
    // RFC), it's called there.  If we're a listener (passive open in the
    // RFC), we'll appear on the pending list with stateClosed, and
    // deleteTcp gets called by the tcp_accept (or tcp_listen) machinery.
    tcp = NULL;
  }

  if (tcp && (flags & flagSyn)) {
    // Incoming SYN.  Might also have data attached (e.g. with SMTP)
    //
    tcp->recvNext = seq + 1;
    if (tcp->state == stateSynSent) {
      tcp->recvInit = seq;
      if (tcp->sendUnack == tcp->sendInit) {
	// Either we've sent our SYN but it hasn't yet been acked (active
	// open with simultaneous open from the other end), or we've made
	// it look that way we because we're really doing a passive open and
	// responding to an incoming SYN.  In either case, (re)transmit our
	// SYN, piggy-backing an ACK.
	sendSmall(tcp, tcp->sendInit, flagAck | flagSyn);
	shouldAck = 0;
      }
      tcp->state = stateSynReceived;
      // which then moves to established, below, if our SYN has been acked
    } else if (seq != tcp->recvInit) {
      // Ignore SYN packet at wrong sequence number
      printf("Out-of-sequenece SYN\n");
      tcp = NULL;
    }
    seq++; // the incoming SYN consumes a sequence number
  }

  if (tcp) {
    // State transitions in response to acknowledgement of FIN or SYN
    //
    switch (tcp->state) {
    case stateSynSent:
      shouldAck = 0;
      break;
    case stateSynReceived:
      if (tcp->sendUnack != tcp->sendInit) {
	tcp->state = stateEstablished;
	condition_signal(tcpAcceptCond);
	condition_broadcast(tcpConnectCond);
      } else {
	shouldAck = 0;
      }
      break;
    case stateFinWait1:
      if (tcp->sendUnack == tcp->sendNext) {
	tcp->state = stateFinWait2;
	condition_broadcast(tcpCloseCond);
      }
      break;
    case stateClosing:
      if (tcp->sendUnack == tcp->sendNext) {
	tcp->state = stateTimeWait;
	condition_broadcast(tcpCloseCond);
      }
      break;
    case stateLastAck:
      if (tcp->sendUnack == tcp->sendNext) {
	tcp->state = stateClosed;
	condition_broadcast(tcpCloseCond);
      }
      shouldAck = 0;
      break;
    }
  }

  if (tcp) {
    // Update our send window
    //
    switch (tcp->state) {
    case stateEstablished:
    case stateCloseWait:
      tcp->sendWindow = ntohs(tcpHeader->window);
      condition_broadcast(tcpSendCond);
      break;
    }
  }

  if (tcp) {
    // Process incoming data
    //
    switch (tcp->state) {
    case stateEstablished:
    case stateFinWait1:
    case stateFinWait2:
      if (!tcpProcessData(tcp, buf)) {
	// Enqueue a copy on outOfOrderHead, in arrival order.
	IP *ooo = (IP *)enet_alloc();
	*ooo = *buf;
	ooo->next = NULL;
	if (tcp->outOfOrderHead) {
	  tcp->outOfOrderTail->next = ooo;
	} else {
	  tcp->outOfOrderHead = ooo;
	}
	tcp->outOfOrderTail = ooo;
      }
      break;
    }
  }
  return (tcp && shouldAck);
}

static void tcpReceiver(IP *buf, Uint32 len, int broadcast) {
  // Up-call from IP when a TCP or ICMP packet has been received.
  //
  // Locate the appropriate connection (creating one if it's a listener);
  // process this packet;
  // re-consider queued out-of-order packets on this connection.
  //
  TCPHeader *tcpHeader = (TCPHeader *)ip_payload(buf);
  if (buf->ip.protocol == ipProtocolICMP) {
    // TEMP: we should pay attention to "no such port", etc.
    return;
  }
  if (payloadChecksum(buf, len) != 0xffff) {
    printf("Bad TCP checksum %04x, len %d\n",
	   payloadChecksum(buf, len), len);
    return;
  }
  TCPPort localPort = ntohs(tcpHeader->dest);
  IPAddr remoteAddr = ntoh(buf->ip.srce);
  TCPPort remotePort = ntohs(tcpHeader->srce);
  mutex_acquire(tcpMutex);
  TCP tcp = findTcp(localPort, remoteAddr, remotePort); 

  if (!tcp) {
    int flags = ntohs(tcpHeader->misc) & 0x3f;
    if (flags == flagSyn) {
      Listener listener = tcpListeners[localPort];
      if (listener) {
	// Create a TCP in stateSynSent, as if we had sent a SYN already;
	// this will make tcpProcessIncoming send a SYN-ACK and move to
	// stateSynReceived.
	tcp = createTcp(localPort, remoteAddr, remotePort);
	tcp->sendNext++;
	tcp->transmitted = tcp->sendNext;
	tcp->state = stateSynSent;
	appendTransmitElem(tcp);
	tcp->nextPending = listener->pendingTail;
	listener->pendingTail = tcp;
	if (!listener->pending) listener->pending = tcp;
	listener->pendingCount++;
      }
    }
  }

  if (!tcp || (tcp && tcp->state == stateClosed)) {
    tcpRejectUnknown(buf);
    tcp = NULL;
  }

  if (tcp) {
    Uint32 prePktSeq = tcp->recvNext;
    int shouldAck = tcpProcessIncoming(tcp, buf);
    // If this packet advanced our state, reconsider out-of-order packets.
    // On outOfOrderHead they are in arrival order.  This is usually, but
    // not certainly, also sequence number order; hence the outer loop.
    int progress = (tcp->recvNext != prePktSeq);
    while (progress) {
      progress = 0;
      if (tcp->state == stateEstablished ||
	  tcp->state == stateFinWait1 ||
	  tcp->state == stateFinWait2) {
	IP *this = tcp->outOfOrderHead;
	IP *prev = NULL;
	while (this) {
	  IP *next = this->next;
	  if (tcpProcessData(tcp, this)) {
	    if (prev) {
	      prev->next = this->next;
	    } else {
	      tcp->outOfOrderHead = this->next;
	    }
	    if (this == tcp->outOfOrderTail) tcp->outOfOrderTail = prev;
	    enet_free((Enet *)this);
	    shouldAck = 1;
	    progress = 1;
	  } else {
	    prev = this;
	  }
	  this = next;
	}
      }
    }
    if (tcp->sendNagled && tcp->sendUnack == tcp->transmitted) {
      sendData(tcp);
    } else if (shouldAck) {
      sendSmall(tcp, tcp->transmitted, flagAck);
    }
  }

  mutex_release(tcpMutex);
}

static void tcpInit() {
  // Initialize TCP globals and register with IP
  if (!tcpMutex) {
    tcpMutex = mutex_create();
    tcpAcceptCond = condition_create();
    tcpConnectCond = condition_create();
    tcpRecvCond = condition_create();
    tcpCloseCond = condition_create();
    tcpCreateCond = condition_create();
    tcpSendCond = condition_create();
    tcpSmallBuf = (IP *)enet_alloc();
    tcpActive = NULL;
    tcpListeners = malloc(65536 * sizeof(Listener *));
    tcpSeed = *cycleCounter;
    ip_register(ipProtocolTCP, tcpReceiver);
    thread_fork(retransmitter, NULL);
  }
}


