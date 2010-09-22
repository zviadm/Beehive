////////////////////////////////////////////////////////////////////////////
//                                                                        //
// network.c                                                              //
//                                                                        //
// ARP, IP, UDP, DHCP (including intial configuration), DNS client        //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "intercore.h"
#include "network.h"

static void networkInit();
// Initialize IP state from DHCP


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Router and ARP                                                         //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define arpOpcodeRequest 1
#define arpOpcodeReply 2
#define arpTypeEnet 1

typedef struct ARPPacket {
  Uint16 hardwareType;
  Uint16 protocolType;
  Octet hardwareSize;
  Octet protocolSize;
  Uint16 opcode;
  Octet senderMAC[6];
  Octet senderIP[4];
  Octet targetMAC[6];
  Octet targetIP[4];
} ARPPacket;

#define arpCacheSize 1023

typedef struct ARPCacheEntry {
  IPAddr addr;
  MAC mac;
  Microsecs time;
} ARPCacheEntry;

static Mutex arpMutex;
static Condition arpCond;
static IPAddr myIP = 0;
static IPAddr mySubnetMask;
static IPAddr myRouter;
static ARPCacheEntry *arpCache;

static void arpInit();

static int ipHash(IPAddr addr) {
  // Return hash of addr for indexing arpCache
  return addr % arpCacheSize;
}

static void arpSend(int op, MAC targetMAC, IPAddr targetIP) {
  // Transmit an ARP request or reply
  Enet *buf = enet_alloc();
  ARPPacket *pkt = (ARPPacket *)buf;
  pkt->hardwareType = htons(arpTypeEnet);
  pkt->protocolType = htons(enetTypeIP);
  pkt->hardwareSize = 6;
  pkt->protocolSize = 4;
  pkt->opcode = htons(op);
  MAC localMAC = enet_localMAC();
  bcopy(&localMAC, &(pkt->senderMAC), 6);
  htonCopy(myIP, (Octet *)&(pkt->senderIP));
  bcopy(&targetMAC, &(pkt->targetMAC), 6);
  htonCopy(targetIP, (Octet *)&(pkt->targetIP));
  enet_send(targetMAC, enetTypeARP, buf, sizeof(ARPPacket));
  enet_free(buf);
}

int arp_getMAC(IPAddr addr, MAC *res) {
  // Find MAC address for given IP address.  Handles ARP and subnet mask.
  // Returns 1 on success, 0 on failure.
  //
  // TEMP: for off-network addresses, we always use our default gateway;
  // we make no attempt to discover other gateways (e.g. we ignore ICMP
  // redirect messages).
  //
  // Broadcast and multicast should be handled elsewhere.
  //
  arpInit();
  mutex_acquire(arpMutex);
  if (myIP && mySubnetMask && myRouter &&
      (addr & mySubnetMask) != (myIP & mySubnetMask)) addr = myRouter;
  int found = 0;
  for (int i = 0; i < 5; i++) {
    ARPCacheEntry entry = arpCache[ipHash(addr)];
    if (entry.addr == addr && thread_now() - entry.time < 60 * 1000000) {
      *res = entry.mac;
      found = 1;
      break;
    }
    arpSend(arpOpcodeRequest, broadcastMAC(), addr);
    condition_timedWait(arpCond, arpMutex, 50000);
  }
  mutex_release(arpMutex);
  return found;
}

void arp_insert(IPAddr addr, MAC mac) {
  // Record an entry in the ARP cache
  arpInit();
  mutex_acquire(arpMutex);
  if (myIP && mySubnetMask && myRouter &&
      (addr & mySubnetMask) != (myIP & mySubnetMask)) addr = myRouter;
  ARPCacheEntry *entry = &(arpCache[ipHash(addr)]);
  entry->addr = addr;
  entry->mac = mac;
  entry->time = thread_now();
  mutex_release(arpMutex);
  condition_broadcast(arpCond);
}

void arp_remove(IPAddr addr) {
  // Remove any existing entry for addr from the ARP cache
  arpInit();
  mutex_acquire(arpMutex);
  if (myIP && mySubnetMask && myRouter &&
      (addr & mySubnetMask) != (myIP & mySubnetMask)) addr = myRouter;
  ARPCacheEntry *entry = &(arpCache[ipHash(addr)]);
  entry->addr = 0;
  mutex_release(arpMutex);
}

void arpReceiver(MAC srce, Uint16 type, Enet *buf, Uint32 len,
		 int broadcast) {
  // Up-call when an ARP packet has been received
  ARPPacket *pkt = (ARPPacket *)buf;
  if (len >= sizeof(ARPPacket) &&
      ntohs(pkt->hardwareType) == arpTypeEnet &&
      ntohs(pkt->protocolType) == enetTypeIP &&
      pkt->hardwareSize == 6 &&
      pkt->protocolSize == 4) {
    IPAddr senderIP = ntohCopy((Octet *)&(pkt->senderIP));
    MAC senderMAC;
    bcopy(&(pkt->senderMAC), &senderMAC, 6);
    IPAddr targetIP = ntohCopy((Octet *)&(pkt->targetIP));
    arp_insert(senderIP, senderMAC); // We learn all; not what RFC 791 says
    if (targetIP == myIP &&
	ntohs(pkt->opcode) == arpOpcodeRequest) {
      arpSend(arpOpcodeReply, senderMAC, senderIP);
    }
  }
}

static void arpInit() {
  // Initialize router globals and register ARP with Enet
  if (!arpMutex) {
    arpMutex = mutex_create();
    arpCond = condition_create();
    arpCache = malloc(arpCacheSize * sizeof(ARPCacheEntry));
    for (int i = 0; i < arpCacheSize; i++) arpCache[i].addr = 0;
    enet_register(enetTypeARP, arpReceiver);
  }
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// IP                                                                     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static Mutex ipMutex = NULL;
static IPAddr ipBroadcast;      // 255.255.255.255
static IPReceiver *ipProtocols; // receivers, indexed by protocol

static void ipDiscard(IP *buf, Uint32 len, int broadcast) {
  // Default handler for an unsupported IP protocols
  icmp_bounce(buf, broadcast,
	      icmpTypeDestinationUnreachable,
	      icmpCodeProtocolUnreachable);
  printf("Unexpected IP protocol %d\n", buf->ip.protocol);
}

static Uint16 ipChecksum(Uint32 res, Octet *buf, Uint32 len) {
  // Return the ip checksum for "len" bytes of data in "buf", plus
  // previously accumulated "res" (for the TCP/UDP pseudo-header)
  // We perform everything in network byte order.
  for (int i = 0; (i < (len >> 2) << 2); i += 4) {
    Uint32 w = *(Uint32 *)(buf+i);
    res += (w & 65535) + (w >> 16);
  }
  // fix up odd bytes, if any
  if ((len & 3) != 0) {
    Uint32 lastW = *(Uint32 *)(buf+((len>>2)<<2));
    if ((len & 3) == 1) {
      res += lastW & 255;
    } else {
      res += lastW & 65535;
      if ((len & 3) == 3) {
	res += (lastW >> 16) & 255;
      }
    }
  }
  res = (res & 65535) + (res >> 16);
  res = (res & 65535) + (res >> 16);
  if (res == 65535) return 65535;
  return ~(Uint16)res;
}

static Uint16 ipHeaderChecksum(IP *buf) {
  return ipChecksum(0, (Octet *)buf, ip_headerSize(buf));
}

Uint16 payloadChecksum(IP *buf, Uint32 len) {
  // Return the UDP/TCP checksum for packet with given UDP/TCP length.
  // "len" includes UDP/TCP header, but not IP header.
  // Result includes the "pseudo-header" additions.
  // We perform everything in network byte order.
  Uint32 res = (buf->ip.protocol << 8);
  res += htons(len);
  Uint32 w = buf->ip.srce;
  res += (w & 65535) + (w >> 16);
  w = buf->ip.dest;
  res += (w & 65535) + (w >> 16);
  return ipChecksum(res, (Octet *)buf + ip_headerSize(buf), len);
}

static IPReceiver ip_getReceiver(Octet protocol) {
  // Return current up-call handler for given protocol
  IPReceiver r;
  mutex_acquire(ipMutex);
  r = ipProtocols[protocol];
  mutex_release(ipMutex);
  return r;
}

static int ipHeaderValid(IP *buf) {
  // Return true iff given IP packet has a valid header
  return ((buf->ip.versionAndLen >> 4) & 15) == 4 &&
    ipHeaderChecksum(buf) == 0xffff;
}

static int ipIsBroadcast(IPAddr addr) {
  // Return true iff addr is an IP broadcast or multicast address
  if (addr == ipBroadcast) return 1; // IP local broadcast
  if (myIP && (addr & ~mySubnetMask) == (ipBroadcast & ~mySubnetMask)) {
    return 1; // IP subnet broadcast
  }
  if (addr >> 28 == 14) return 1; // IP multicast
  // We should also allow for "all subnets within network" broadcasts,
  // but we don't.  And nobody uses that anyway.  I think.
  return 0;
}

static void ipReceiver(MAC srce, Uint16 type, Enet *buf, Uint32 len,
		       int broadcast) {
  // Up-call when an IP packet has been received.
  IP *ipBuf = (IP *)buf;
  IPAddr ipSrce = ntoh(ipBuf->ip.srce);
  IPAddr ipDest = ntoh(ipBuf->ip.dest);
  broadcast |= ipIsBroadcast(ipDest);
  if (!ipHeaderValid(ipBuf)) {
    unsigned int *foo = (unsigned int *)ipBuf;
    printf("Invalid IP header at %08x: %08x %08x %08x %08x %08x\n",
	   (unsigned int)foo,
	   ntoh(foo[0]), ntoh(foo[1]), ntoh(foo[2]),
	   ntoh(foo[3]), ntoh(foo[4]));
  } else if ((myIP && ipDest != myIP) && !broadcast) {
    // We should also accept broadcasts directed to all subnets
    // on our network, according to RFC 1122.  But nobody uses that.
    printf("Non-local IP destination %08x\n", ipDest);
  } else if (ipSrce >> 24 == 127 || ipSrce == ipBroadcast ||
	     (myIP &&
	      (ipSrce & ~mySubnetMask) == (ipBroadcast & ~mySubnetMask))) {
    printf("Illegal IP source %08x\n (bcast %08x, ~mask %08x)\n",
	   ipSrce, ipBroadcast, ~mySubnetMask);
  } else {
    arp_insert(ipSrce, srce);
    IPReceiver r = ip_getReceiver(ipBuf->ip.protocol);
    r(ipBuf, ip_payloadSize(ipBuf), broadcast);
  }
}

void ip_register(Octet protocol, IPReceiver receiver) {
  // Register up-call handler for an IP protocol; NULL to disable
  networkInit();
  mutex_acquire(ipMutex);
  ipProtocols[protocol] = (receiver ? receiver : ipDiscard);
  mutex_release(ipMutex);
}

void ip_setSrce(IP *buf) {
  // Set srce address in buf, appropriately for dest address.
  networkInit();
  mutex_acquire(arpMutex);
  buf->ip.srce = hton(myIP);
  mutex_release(arpMutex);
}

void ip_send(IP *buf, Uint32 len, Octet ttl, Octet tos) {
  // Send an IP packet.  Protocol, versionAndLen, srce, and dest are set
  // by caller.  "len" does not include the IP header
  networkInit();
  buf->ip.service = tos;
  buf->ip.len = htons(len + ip_headerSize(buf));
  buf->ip.id = htons(enet_random() & 65535);
  buf->ip.frag = htons(0);
  buf->ip.ttl = (ttl == 0 ? 64 : ttl); // From RFC 1700
  buf->ip.checksum = 0;
  buf->ip.checksum = ipHeaderChecksum(buf);
  MAC destMAC;
  IPAddr destAddr = ntoh(buf->ip.dest);
  if (buf->ip.dest == hton(ipBroadcast)) {
    destMAC = broadcastMAC();
  } else if ((buf->ip.dest & 255) == 127) {
    // Local loopback
    ipReceiver(enet_localMAC(), enetTypeIP,
	       (Enet *)buf, len + ip_headerSize(buf), 0);
    return;
  } else if (!arp_getMAC(destAddr, &destMAC)) {
    printf("No MAC address for %08x\n", destAddr);
    return;
  }
  enet_send(destMAC, enetTypeIP, (Enet *)buf, len + ip_headerSize(buf));
}

static void ipInit() {
  // Initialize IP globals and register with Enet
  ipBroadcast = ip_fromQuad(255,255,255,255);
  ipMutex = mutex_create();
  ipProtocols = malloc(256 * sizeof(IPReceiver));
  for (int i = 0; i < 256; i++) ipProtocols[i] = ipDiscard;
  enet_register(enetTypeIP, ipReceiver);
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// ICMP                                                                   //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static Mutex icmpMutex = NULL;
static ICMPReceiver *icmpTypes; // receivers, indexed by ICMP type

static Uint16 icmpChecksum(IP *buf, Uint32 len) {
  // Return ICMP payload checksum.
  // "len" includes ICMP header, but not IP header
  return ipChecksum(0, (Octet *)buf + ip_headerSize(buf), len);
}

static ICMPReceiver icmp_getReceiver(Octet type) {
  // Return current up-call handler for given ICMP type
  ICMPReceiver r;
  mutex_acquire(icmpMutex);
  r = icmpTypes[type];
  mutex_release(icmpMutex);
  return r;
}

static void icmpDiscard(IP *buf, Uint32 len) {
  // Default handler for incoming ICMP
  ICMPHeader *icmpHeader = (ICMPHeader *)ip_payload(buf);
  printf("Unexpected ICMP type %d\n", icmpHeader->type);
}

static void icmpEcho(IP *buf, Uint32 len) {
  // Handler for incoming ICMP Echo Request
  ICMPHeader *icmpHeader = (ICMPHeader *)ip_payload(buf);
  buf->ip.dest = buf->ip.srce;
  ip_setSrce((IP *)buf);
  icmpHeader->type = icmpTypeEchoReply;
  icmpHeader->checksum = 0;
  icmpHeader->checksum = icmpChecksum(buf, len);
  ip_send(buf, len, 0, 0);
}

static void icmpTransportProblem(IP *buf, Uint32 len) {
  // Handler for incoming ICMP that should be passed to the transport layer
  ICMPHeader *icmpHeader = (ICMPHeader *)ip_payload(buf);
  IP *bouncedIP = (IP *)(ip_payload(buf) + sizeof(ICMPHeader));
  if (ipHeaderValid(bouncedIP) && ntoh(bouncedIP->ip.srce) == myIP &&
      bouncedIP->ip.protocol != ipProtocolICMP) {
    Octet type = icmpHeader->type;
    Octet code = icmpHeader->code;
    if ((type == icmpTypeDestinationUnreachable &&
	 (code == icmpCodeProtocolUnreachable ||
	  code == icmpCodePortUnreachable)) ||
	type == icmpTypeTimeExceeded) {
      arp_remove(ntoh(bouncedIP->ip.dest));
    }
    IPReceiver r = ip_getReceiver(bouncedIP->ip.protocol);
    if (r != ipDiscard) r(buf, len, 0);
  }
}

static void icmpReceiver(IP *buf, Uint32 len, int broadcast) {
  // Up-call when am ICMP packet has been received
  ICMPHeader *icmpHeader = (ICMPHeader *)ip_payload(buf);
  if (icmpChecksum(buf, len) != 0xffff) {
    printf("Bad ICMP checksum\n");
  } else if (!broadcast) {
    ICMPReceiver r = icmp_getReceiver(icmpHeader->type);
    r(buf, len);
  }
}

void icmp_register(Octet type, ICMPReceiver receiver) {
  // Register up-call handler for an ICMP type; NULL to disable
  networkInit();
  mutex_acquire(icmpMutex);
  icmpTypes[type] = (receiver ? receiver : icmpDiscard);
  mutex_release(icmpMutex);
}

void icmp_send(ICMP *buf, Uint32 len) {
  // Send ICMP packet in "buf".
  // "len" is length of the ICMP payload (excluding ICMP header).
  // Destination address, ICMP type, and ICMP code are set by caller.
  buf->ip.protocol = ipProtocolICMP;
  buf->ip.versionAndLen = 0x45; // IPv4, 5 words in header
  ip_setSrce((IP *)buf);
  buf->icmp.checksum = 0;
  buf->icmp.checksum = icmpChecksum((IP *)buf, len + sizeof(ICMPHeader));
  ip_send((IP *)buf, len + sizeof(ICMPHeader), 0, 0);
}

void icmp_bounce(IP *buf, int broadcast, Octet type, Octet code) {
  // Send an ICMP bounce in response to the given incoming packet.
  //
  // Overwrites "buf" (to avoid allocating its own).
  // The bounce includes the IP header and 8 bytes of payload from "buf".
  // Omits bounces prohibited by RFC 1122 (e.g. to broadcast addresses).
  //
  if (broadcast || buf->ip.protocol == ipProtocolICMP) return;
  IPAddr dest = ntoh(buf->ip.srce);
  if (dest == 0) return;
  if (ipIsBroadcast(dest)) return;
  Uint16 frag = ntohs(buf->ip.frag) & 0x1fff;
  if (frag) return; // non-first fragment
  Octet tempPayload[icmpPayloadSize];
  Uint32 dataLen = ip_headerSize(buf) + 8;
  if (dataLen > icmpPayloadSize) dataLen = icmpPayloadSize;
  bcopy(buf, tempPayload, dataLen);
  ICMP *icmpBuf = (ICMP *)buf;
  icmpBuf->icmp.type = type;
  icmpBuf->icmp.code = code;
  bcopy(tempPayload, &(icmpBuf->data), dataLen);
  icmpBuf->ip.dest = hton(dest);
  icmp_send(icmpBuf, dataLen);
}

static void icmpInit() {
  // Register with IP globals and register with IP
  icmpMutex = mutex_create();
  icmpTypes = malloc(256 * sizeof(ICMPReceiver));
  for (int i = 0; i < 256; i++) icmpTypes[i] = icmpDiscard;
  icmp_register(icmpTypeDestinationUnreachable, icmpTransportProblem);
  icmp_register(icmpTypeSourceQuench, icmpTransportProblem);
  icmp_register(icmpTypeEchoRequest, icmpEcho);
  icmp_register(icmpTypeTimeExceeded, icmpTransportProblem);
  icmp_register(icmpTypeParameterProblem, icmpTransportProblem);
  ip_register(ipProtocolICMP, icmpReceiver);
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// UDP                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef struct UDPElem {
  struct UDPElem *prev;
  struct UDPElem *next;
  IP *buf;
  UDPPort dest;
  int len; // UDP payload length or negative return code
} *UDPElem;

static Mutex udpMutex = NULL;
static Condition udpCond = NULL;
static UDPElem udpHead = NULL;   // head of received UDP packet queue
static UDPElem udpTail = NULL;   // tail of received UDP packet queue
static UDPReceiver *udpPorts;    // receivers, indexed by port number

static void udpDiscard(IP *buf, int len, int broadcast, UDPPort port) {
  // Default handler for an unused UDP port
  UDPHeader *udpHeader = (UDPHeader *)ip_payload(buf);
  icmp_bounce(buf, broadcast,
	      icmpTypeDestinationUnreachable,
	      icmpCodePortUnreachable);
}

static void udpEnqueue(IP *buf, int len, int broadcast, UDPPort dest) {
  // Handler for a UDP port set up for blocking receive
  // len is UDP payload length or error code; buf is NULL for error codes.
  IP *newBuf = NULL;
  if (buf != NULL) {
    newBuf = (IP *)enet_alloc();
    bcopy(buf, newBuf, len + ip_headerSize(buf) + sizeof(UDPHeader));
  }
  UDPElem this = malloc(sizeof(struct UDPElem));
  this->next = NULL;
  this->buf = newBuf;
  this->len = len;
  this->dest = dest;
  mutex_acquire(udpMutex);
  if (udpHead == NULL) {
    udpHead = this;
    udpTail = this;
    this->prev = NULL;
  } else {
    this->prev = udpTail;
    udpTail->next = this;
    udpTail = this;
  }
  mutex_release(udpMutex);
  condition_broadcast(udpCond);
}

static void udpDeliver(IP *buf, int len, int broadcast, UDPPort dest) {
  // Deliver packet or negative result to handler for given UDP port
  // "len" is UDP payload length, or negative return code
  UDPReceiver r;
  mutex_acquire(udpMutex);
  r = udpPorts[dest];
  mutex_release(udpMutex);
  r(buf, len, broadcast, dest);
}

static void udpReceiver(IP *buf, Uint32 len, int broadcast) {
  // Up-call from IP when a UDP or ICMP packet has been received
  UDPHeader *udpHeader = (UDPHeader *)ip_payload(buf);
  if (buf->ip.protocol == ipProtocolICMP) {
    ICMPHeader *icmpHeader = (ICMPHeader *)ip_payload(buf);
    IP *bouncedIP = (IP *)(ip_payload(buf) + sizeof(ICMPHeader));
    UDPHeader *bouncedUDP = (UDPHeader *)ip_payload(bouncedIP);
    UDPPort dest = ntohs(bouncedUDP->srce);
    Octet type = icmpHeader->type;
    if (type == icmpTypeDestinationUnreachable ||
	type == icmpTypeTimeExceeded) {
      udpDeliver(NULL, udpRecvPortUnreachable, broadcast, dest);
    } // We ignore Source Quench and Parameter Problem
  } else if (udpHeader->checksum != 0 &&
      payloadChecksum(buf, ntohs(udpHeader->len)) != 0xffff) {
    printf("Bad UDP checksum\n");
  } else if (htons(udpHeader->len) != len) {
    printf("Bad UDP length\n");
  } else {
    // Deliver the packet, by up-call or by blocking receive.
    UDPPort dest = ntohs(udpHeader->dest);
    udpDeliver(buf, len - sizeof(UDPHeader), broadcast, dest);
  }
}

void udp_register(UDPPort p, UDPReceiver receiver) {
  networkInit();
  mutex_acquire(udpMutex);
  udpPorts[p] = (receiver ? receiver : udpEnqueue);
  mutex_release(udpMutex);
}

UDPPort udp_allocPort(UDPReceiver receiver) {
  networkInit();
  UDPPort res;
  mutex_acquire(udpMutex);
  for (;;) {
    res = enet_random() & 65535;
    if (res > 1024 && udpPorts[res] == udpDiscard) break;
  }
  udpPorts[res] = (receiver ? receiver : udpEnqueue);
  mutex_release(udpMutex);
  return res;
}

void udp_freePort(UDPPort p) {
  networkInit();
  mutex_acquire(udpMutex);
  udpPorts[p] = udpDiscard;
  mutex_release(udpMutex);
}

int udp_recv(IP ** buf, UDPPort p, Microsecs microsecs) {
  networkInit();
  *buf = NULL;
  int len = udpRecvTimeout;
  mutex_acquire(udpMutex);
  for (;;) {
    UDPElem this = udpHead;
    while (this != NULL) {
      if (this->dest == p) break;
      this = this->next;
    }
    if (this != NULL) {
      if (this == udpHead) {
	udpHead = udpHead->next;
      } else {
	this->prev->next = this->next;
      }
      if (this == udpTail) {
	udpTail = NULL;
      } else {
	this->next->prev = this->prev;
      }
      *buf = this->buf;
      len = this->len;
      free(this);
      break;
    }
    if (condition_timedWait(udpCond, udpMutex, microsecs)) break;
  }
  mutex_release(udpMutex);
  return len;
}

void udp_recvDone(IP * buf) {
  networkInit();
  if (buf) enet_free((Enet *)buf);
}

void udp_send(UDP *buf, Uint32 len) {
  // Send UDP packet in "buf".
  // "len" is length of the UDP payload (excluding header).
  // Destination address and port and source port are set by caller.
  networkInit();
  buf->ip.protocol = ipProtocolUDP;
  buf->ip.versionAndLen = 0x45; // IPv4, 5 words in header
  ip_setSrce((IP *)buf);
  buf->udp.len = htons(len + sizeof(UDPHeader));
  buf->udp.checksum = 0;
  buf->udp.checksum = payloadChecksum((IP *)buf, len + sizeof(UDPHeader));
  ip_send((IP *)buf, len + sizeof(UDPHeader), 0, 0);
}

static void udpInit() {
  // Initialize UDP globals and register with IP
  udpMutex = mutex_create();
  udpCond = condition_create();
  udpHead = NULL;
  udpPorts = malloc(65536 * sizeof(UDPReceiver));
  for (int i = 0; i < 65536; i++) udpPorts[i] = udpDiscard;
  ip_register(ipProtocolUDP, udpReceiver);
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// DNS                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define maxServers 4
typedef IPAddr DNSAddrs[maxServers];

// well-known server port
#define dnsPort 53

#define dnsTypeA 1
#define dnsClassIN 1

#define dnsRetryLimit 8    /* maximum number of transmission attempts */
#define dnsTimeLimit 3000000 /* receive timeout, in microseconds */

typedef struct DNSHeader {
  short id;
  short misc;
  short qdCount;
  short anCount;
  short nsCount;
  short arCount;
} DNSHeader;

static Mutex dnsMutex = NULL;
static DNSAddrs myDNS;

void skipName(Octet * recvData, int * pos, int recvLen) {
  // Update "pos" to skip past a "name" in recvData
  while (*pos < recvLen) {
    int len = recvData[*pos];
    (*pos)++;
    if (len == 0) break; // null terminator
    if ((len & 0xc0) == 0xc0) { (*pos)++; break; } // pointer
    (*pos) += len;
  }
}

int dns_lookup(char *name, IPAddr *res) {
  if (sizeof(DNSHeader) + strlen(name) + 1 + 2 * 2 >
      udpPayloadSize) return dnsNameTooLong;
  UDP *dnsSendBuf = (UDP *)enet_alloc();
  UDPPort local = udp_allocPort(NULL);
  DNSHeader * sendHeader = (DNSHeader *)&(dnsSendBuf->data[0]);
  int myReqId;
  myReqId = enet_random() & 65535;
  sendHeader->id = htons(myReqId);
  sendHeader->misc = htons(0x100);
  sendHeader->qdCount = htons(1);
  sendHeader->anCount = htons(0);
  sendHeader->nsCount = htons(0);
  sendHeader->arCount = htons(0);
  // We write one entry into the Question section, starting with "name".
  int pos = sizeof(DNSHeader);
  int lenPos = pos;
  int i;
  for (i = 0; ; i++) {
    if (name[i] == 0) break;
    if (name[i] == '.') {
      dnsSendBuf->data[lenPos] = pos - lenPos;
      pos++;
      lenPos = pos;
    } else {
      pos++;
      dnsSendBuf->data[pos] = name[i];
    }
  }
  if (pos != lenPos) {
    dnsSendBuf->data[lenPos] = pos - lenPos;
    pos++;
  }
  dnsSendBuf->data[pos] = 0;
  pos++;
  htonsCopy(dnsTypeA, &(dnsSendBuf->data[pos]));
  pos +=2;
  htonsCopy(dnsClassIN, &(dnsSendBuf->data[pos]));
  pos +=2;
  dnsSendBuf->udp.dest = htons(dnsPort);
  dnsSendBuf->udp.srce = htons(local);
  int tries;
  int tryServer = 0; // next server to try
  Uint32 recvLen;
  IP *recvBuf;
  DNSHeader *recvHeader;
  Octet *recvData;
  int recvMisc; // "misc" field from response header
  int recvCode; // return-code field from recvMisc;
  for (tries = 0; tries < dnsRetryLimit; tries++) {
    mutex_acquire(dnsMutex);
    if (tryServer >= maxServers || myDNS[tryServer] == 0) tryServer = 0;
    if (myDNS[tryServer] == 0) return dnsNoServer;
    dnsSendBuf->ip.dest = hton(myDNS[tryServer]);
    tryServer++;
    mutex_release(dnsMutex);
    udp_send(dnsSendBuf, pos);
    recvLen = udp_recv(&recvBuf, local, dnsTimeLimit);
    if (recvBuf) {
      // not timed out
      recvHeader = (DNSHeader *)udp_payload(recvBuf);
      recvData = udp_payload(recvBuf);
      recvMisc = ntohs(recvHeader->misc);
      recvCode = recvMisc & 0xf;
      if (recvLen >= 0 &&  ntohs(recvHeader->id) == myReqId &&
	  // recvMisc top bit indicates "response"
	  (recvMisc & 0x8000) != 0 &&
	  // recvCode 2 = server failure
	  //          4 = not implemented
	  //         >5 = undefined
	  recvCode != 2 && recvCode != 4 && recvCode <= 5) break;
    }
    if (recvBuf) udp_recvDone(recvBuf);
  }
  udp_freePort(local);
  enet_free((Enet *)dnsSendBuf);
  if (tries >= dnsRetryLimit) return dnsTimeout;
  // We have a response to our question
  if (recvCode == 1) return dnsMalformedQuery;
  if (recvCode == 3) return dnsNameNotFound;
  if (recvCode == 5) return dnsServerRefused;
  if (ntohs(recvHeader->anCount) == 0) return dnsNameHasNoAddress;
  pos = sizeof(DNSHeader);
  // skip stuff in the "Question" section
  int rqdCount = ntohs(recvHeader->qdCount);
  for (i = 0; i < rqdCount; i++) {
    if (pos >= recvLen) return dnsMalformedResponse;
    skipName(recvData, &pos, recvLen);
    pos += 4; // qType and qClass
  }
  // "pos" is start of "Answer" section
  // TEMP: we really should verify that the name/type/class/rdLength match.
  // Meanwhile, we just grab the first IP address.
  skipName(recvData, &pos, recvLen);
  pos += 10; // type, class, TTL, rdLength
  *res = ntohCopy(&(recvData[pos]));
  pos += 4;
  udp_recvDone(recvBuf);
  return 0;
}

static void dnsInit() {
  // Initialize DNS globals
  dnsMutex = mutex_create();
  for (int i = 0; i < maxServers; i++) myDNS[i] = 0;
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Initialization                                                         //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define bootpsPort (67)
#define bootpcPort (68)

#define dhcpTypeDiscover 1
#define dhcpTypeOffer 2
#define dhcpTypeRequest 3
#define dhcpTypeDecline 4
#define dhcpTypeAck 5
#define dhcpTypeNak 6
#define dhcpTypeRelease 7

typedef struct DHCPHeader {
  Octet messageType;
  Octet hardwareType;
  Octet hardwareAddrLength;
  Octet hops;
  Uint32 transactionID;
  Uint16 seconds;
  Uint16 flags;
  Uint32 clientIP;
  Uint32 yourIP;
  Uint32 nextServerIP;
  Uint32 relayAgentIP;
  Octet hardwareAddr[16];
  Octet sname[64];
  Octet file[128];
  Uint32 magicCookie;
  // Followed by the options area
} DHCPHeader;

static void readDhcpOptions(Octet *optData,
			    Uint32 optLen,
			    Octet *messageType,
			    IPAddr *router,
			    IPAddr *subnetMask,
			    DNSAddrs *dnsAddr) {
  for (int i = 0; i < maxServers; i++) (*dnsAddr)[i] = 0;
  int pos = 0;
  for (;;) {
    if (pos >= optLen) {
      printf("Missing end option\n");
      break;
    }
    int optionType = *optData;
    optData++;
    pos++;
    if (optionType == 255) break;
    int optionLength = *optData;
    optData++;
    pos++;
    if (optionType == 53) { // DHCP message type
      if (messageType) *messageType = *optData;
    } if (optionType == 1) {
      if (subnetMask) *subnetMask = ntohCopy(optData);
    } else if (optionType == 3) {
      if (router) *router = ntohCopy(optData);
    } if (optionType == 6) {
      if (dnsAddr) {
	int addrs = optionLength >> 2;
	if (addrs > maxServers) addrs = maxServers;
	for (int i = 0; i < addrs; i++) {
	  (*dnsAddr)[i] = ntohCopy(optData);
	  optData += 4;
	  optionLength -= 4;
	  pos += 4;
	}
      }
    }
    optData += optionLength;
    pos += optionLength;
  }
}

static void configInit() {
  // Get IP and DNS configuration via DHCP.
  //
  // TEMP: never fails, just keeps on trying.
  //
  UDP *dhcpSendBuf = (UDP *)enet_alloc();
  DHCPHeader *dhcp = (DHCPHeader *)&(dhcpSendBuf->data);
  dhcpSendBuf->ip.dest = ipBroadcast;
  dhcpSendBuf->udp.dest = htons(bootpsPort);
  dhcpSendBuf->udp.srce = htons(bootpcPort);
  udp_register(bootpcPort, NULL);
  dhcp->messageType = 1; // boot request
  dhcp->hardwareType = 1; // Ethernet
  dhcp->hardwareAddrLength = 6;
  dhcp->hops = 0;
  mutex_acquire(udpMutex);
  dhcp->transactionID = enet_random();
  mutex_release(udpMutex);
  dhcp->seconds = htons(0);
  //  dhcp->flags = htons(0x8000);
  dhcp->flags = 0; // Beehive doesn't receive broadcasts yet
  dhcp->clientIP = 0;
  dhcp->yourIP = 0;
  dhcp->nextServerIP = 0;
  dhcp->relayAgentIP = 0;
  MAC localMAC = enet_localMAC();
  bcopy(&localMAC, &(dhcp->hardwareAddr), 6);
  dhcp->sname[0] = 0;
  dhcp->file[0] = 0;
  dhcp->magicCookie = hton(0x63825363);
  for (;;) {
    IP *recvd;
    Uint32 recvdLen;
    Uint32 pos = sizeof(DHCPHeader);
    dhcpSendBuf->data[pos] = 53;  // DHCP message type
    pos++;
    dhcpSendBuf->data[pos] = 1;   // length
    pos++;
    dhcpSendBuf->data[pos] = dhcpTypeDiscover;
    pos++;
    dhcpSendBuf->data[pos] = 255; // end of options
    pos++;
    udp_send(dhcpSendBuf, pos);
    recvdLen = udp_recv(&recvd, bootpcPort, 5000000);
    if (recvd) {
      DHCPHeader *offer = (DHCPHeader *)udp_payload(recvd);
      Octet messageType;
      readDhcpOptions(udp_payload(recvd) + sizeof(DHCPHeader),
		      recvdLen - sizeof(DHCPHeader),
		      &messageType,
		      NULL, NULL, NULL);
      if (messageType == dhcpTypeOffer) {
	pos = sizeof(DHCPHeader);
	dhcpSendBuf->data[pos] = 50;  // Requested IP address
	pos++;
	dhcpSendBuf->data[pos] = 4;   // length
	pos++;
	htonCopy(ntoh(offer->yourIP), &(dhcpSendBuf->data[pos]));
	pos += 4;
	dhcpSendBuf->data[pos] = 53;  // DHCP message type
	pos++;
	dhcpSendBuf->data[pos] = 1;   // length
	pos++;
	dhcpSendBuf->data[pos] = dhcpTypeRequest;
	pos++;
	dhcpSendBuf->data[pos] = 54;  // Server identifier
	pos++;
	dhcpSendBuf->data[pos] = 4;   // length
	pos++;
	htonCopy(ntoh(offer->nextServerIP), &(dhcpSendBuf->data[pos]));
	pos += 4;
	dhcpSendBuf->data[pos] = 55;  // Parameter request list
	pos++;
	dhcpSendBuf->data[pos] = 3;   // length
	pos++;
	dhcpSendBuf->data[pos] = 1;   // subnet mask
	pos++;
	dhcpSendBuf->data[pos] = 3;   // router
	pos++;
	dhcpSendBuf->data[pos] = 6;   // DNS servers
	pos++;
	dhcpSendBuf->data[pos] = 255; // end of options
	pos++;
	udp_recvDone(recvd);
	udp_send(dhcpSendBuf, pos);
	recvdLen = udp_recv(&recvd, bootpcPort, 5000000);
	if (recvd) {
	  DHCPHeader *ack = (DHCPHeader *)udp_payload(recvd);
	  IPAddr yourIP = ntoh(ack->yourIP);
	  Octet messageType;
	  IPAddr router;
	  IPAddr subnetMask;
	  DNSAddrs dnsAddrs;
	  readDhcpOptions(udp_payload(recvd) + sizeof(DHCPHeader),
			  recvdLen - sizeof(DHCPHeader),
			  &messageType,
			  &router,
			  &subnetMask,
			  &dnsAddrs);
	  udp_recvDone(recvd);
	  if (messageType == dhcpTypeAck) {
	    mutex_acquire(arpMutex);
	    myIP = yourIP;
	    mySubnetMask = subnetMask;
	    myRouter = router;
	    mutex_release(arpMutex);
	    mutex_acquire(dnsMutex);
	    for (int i = 0; i < maxServers; i++) myDNS[i] = dnsAddrs[i];
	    mutex_release(dnsMutex);
	    break;
	  }
	} else {
	  printf("No response to DHCP request\n");
	}
      }
    } else {
      printf("No response to DHCP discover\n");
    }
    thread_sleep(1000000); // sleep before retransmitting
  }
  udp_freePort(bootpcPort);
  enet_free((Enet *)dhcpSendBuf);
}

static void networkInit() {
  if (!ipMutex) {
    arpInit();
    ipInit();
    icmpInit();
    udpInit();
    dnsInit();
    configInit();
  }
}

