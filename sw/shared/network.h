////////////////////////////////////////////////////////////////////////////
//                                                                        //
// network.h                                                              //
//                                                                        //
// Basic networking access: ARP, DHCP, IP, ICMP, UDP, TCP, DNS, TFTP      //
//                                                                        //
////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// NOTE:                                                                  //
//                                                                        //
// This is still a work-in-progress, and even when complete it is not     //
// intended to match the TCP/IP stack in a full-scale system.  It is      //
// intended to work and inter-operate correctly, though.                  //
//                                                                        //
// There are some functional omissions:                                   //
//   - the IP layer doesn't do packet fragmentation or re-assembly;       //
//   - the IP layer uses only a single gateway, provided by DHCP;         //
//   - the IP layer doesn't refresh its DHCP lease;                       //
//   - TCP doesn't make any attempt to deal with smaller MTU sizes;       //
//   - TCP doesn't handle "urgent" data;                                  //
//   - there is no way to add options to outbound IP or TCP packets,      //
//     although they are tolerated in received packets (and used in the   //
//     outbound SYN packet).                                              //
//                                                                        //
// There are also performance shortcomings (in the TCP layer):            //
//   - the retransmission strategy is, at best, naive;                    //
//   - there is no slow-start, nor congestion avoidance algorithms        //
//     (but Nagle's algorithm is included).                               //
//                                                                        //
// The TCP interface is designed to support blocking receive calls from   //
// a multi-threaded application, not a non-blocking event-style usage.    //
// You can timeout threads blocked in tcp_send or tcp_recv by calling     //
// tcp_abort (not tcp_close!) from another thread.  The implementation    //
// reports an error if data or FIN transmissions are not acknowledged     //
// after a reasonable amount of retransmission.  The client is            //
// responsible for choosing a suitable timeout for tcp_connect.           //
//                                                                        //
// The lower layers (MQ, raw Ethernet, IP, ICMP, and UDP) are designed to //
// allow non-blocking usage by doing up-calls when a packet arrives.  The //
// up-calls occur with no context switches and no packet copying.         //
//                                                                        //
// There is a centralized buffer pool: see enet_alloc                     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////


#ifndef _NETWORK_H
#define _NETWORK_H

#include "threads.h"


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Network data types, and their conversion                               //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef unsigned char Octet;
typedef unsigned short Uint16;
typedef unsigned int Uint32;

static Uint16 htons(Uint16 n) {
  // Convert 16-bit value from local hardware to network byte order
  return ((n >> 8) & 255) | ((n & 255) << 8);
}

static Uint16 ntohs(Uint16 n) {
  // Convert 16-bit value from network to local hardware byte order
  return htons(n);
}

static void htonsCopy(Uint16 n, Octet * dest) {
  // Copy 16-bit local hardware value into network value in unaligned memory
  dest[0] = (n >> 8) & 255;
  dest[1] = n & 255;
}

static Uint16 ntohsCopy(Octet * srce) {
  // Read 16-bit local hardware value from network value in unaligned memory
  return (srce[0] << 8) | srce[1];
}

static Uint32 hton(Uint32 n) {
  // Convert 32-bit value from local hardware to network byte order
  return ((n >> 24) & 255) |
    (((n >> 16) & 255) << 8) |
    (((n >> 8) & 255) << 16) |
    ((n & 255) << 24);
}

static Uint32 ntoh(Uint32 n) {
  // Convert 32-bit value from network to local hardware byte order
  return hton(n);
}

static void htonCopy(Uint32 n, Octet * dest) {
  // Copy 32-bit local hardware value into network value in unaligned memory
  dest[0] = (n >> 24) & 255;
  dest[1] = (n >> 16) & 255;
  dest[2] = (n >> 8) & 255;
  dest[3] = n & 255;
}

static Uint32 ntohCopy(Octet * srce) {
  // Read 32-bit local hardware value from network value in unaligned memory
  return (srce[0] << 24) |
    (srce[1] << 16) |
    (srce[2] << 8) |
    srce[3];
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Message queue dispatcher                                               //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

// The message queue dispatcher is the base of the world for receiving
// inter-core messages, including those corresponding to incoming Ethernet
// packets.
//
// Reception works by up-calls, dispatched at each layer to registered
// handlers.  The up-calls execute in the dedicated system message receive
// thread, and are expected to terminate rapidly.  Buffers are on loan to
// the handlers for the duration of the up-call, and then revert to the
// system.

typedef unsigned int MQMessage[63];

typedef void (* MQReceiver)(unsigned int srce, unsigned int type,
          MQMessage *msg, unsigned int len);
// Up-call handler for received inter-core messages.
// len is the message payload length.

void mq_register(unsigned int core, MQReceiver receiver);
// Register up-call handler for messages from a core; NULL to disable
//
// The system registers an MQReceiver for the Ethernet core.

////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Ethernet                                                               //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define enetTypeIP (0x0800)
#define enetTypeARP (0x0806)

typedef struct MAC {          // Ethernet MAC address, in network byte order
  Octet bytes[6];
} MAC;

#define enetPayloadSize (1500)

typedef struct Enet {         // Ethernet packet payload, without header
  Octet data[enetPayloadSize];
  struct Enet *next;
} Enet;
// Note that "struct Enet" has a length that's 0 mod 32.  A 32-byte-aligned
// array of them will have each member also 32-byte-aligned.
// The "next" field is used internally for a free list (enet_free).
// Clients can do whatever they want with this field in a non-freed buffer.

typedef void (* EnetReceiver)(MAC srce, Uint16 type, Enet *buf, Uint32 len,
            int broadcast);
// Up-call handler for received Ethernet packets.
// len is the Ethernet payload length.
// "broadcast" is a boolean indicating packet was a link-level broadcast.
//
// The up-calls execute in the dedicated system message receive
// thread, and are expected to terminate rapidly.  Buffers are on loan to
// the handlers for the duration of the up-call, and then revert to the
// system.  Buffers are data-cache aligned.

void enet_init();
// Initialize globals, and register with MQ
// Called implicitly as needed fromother entry points

MAC broadcastMAC();
// Returns Ethernet broadcast address

Enet *enet_alloc();
// Allocate a buffer from the global pool.
// The buffer is data-cache aligned.

void enet_free(Enet *buf);
// Free a previously allocated buffer.

MAC enet_localMAC();
// Returns this controller's MAC address

unsigned int enet_random();
// Returns a somewhat random 32-bit integer.
//
// This comes from a simple pseudo-random number generator, augmented by
// the arrival times of Ethernet packets, including broadcasts, measured by
// the hardware cycle counter.

void enet_register(Uint16 protocol, EnetReceiver receiver);
// Register up-call handler for an Ethernet protocol; NULL to disable
//
// The system registers an EnetReceiver for ARP and IP.

void enet_send(MAC dest, Uint16 type, Enet *buf, Uint32 len);
// Send a raw Ethernet packet


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// IP                                                                     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define ipProtocolICMP (1)
#define ipProtocolTCP (6)
#define ipProtocolUDP (17)

typedef Uint32 IPAddr;        // IP address, in hardware order

typedef struct IPHeader {     // static part of IP header
  Octet versionAndLen;        // 0x45 for IPv4 with no options
  Octet service;              // QOS, etc; use 0 normally
  Uint16 len;                 // total length, header + options + payload
  Uint16 id;                  // frag/defrag identifier
  Uint16 frag;                // fragmentation details; use 0 normally
  Octet ttl;                  // remaining hops
  Octet protocol;             // protocol family
  Uint16 checksum;            // IP header checksum, FWIW
  Uint32 srce;
  Uint32 dest;
} IPHeader;

#define ipPayloadSize (enetPayloadSize - sizeof(IPHeader))

typedef struct IP {           // complete IP packet
  IPHeader ip;                // static part of IP header
  Octet data[ipPayloadSize];  // IP options and payload
  struct IP *next;            // not used by IP; available for clients.
} IP;

typedef void (* IPReceiver)(IP *buf, Uint32 len, int broadcast);
// Up-call handler for received IP packets.
// len is the IP payload length.
// "broadcast" is boolean indicating packet was IP or link-level broadcast.
//
// The up-calls execute in the dedicated system message receive
// thread, and are expected to terminate rapidly.  Buffers are on loan to
// the handlers for the duration of the up-call, and then revert to the
// system.  Buffers are data-cache aligned.

static IPAddr ip_fromQuad(Octet a, Octet b, Octet c, Octet d) {
  // Returns hardware integer for the address "a.b.c.d"
  return (a << 24) | (b << 16) | (c << 8) | d;
}

static Uint32 ip_headerSize(IP *buf) {
  // Return the IP header size of a received packet, in Octets
  return (buf->ip.versionAndLen & 15) << 2;
}

static Octet *ip_payload(IP *buf) {
  // Return a pointer to the IP payload area of a received packet
  return (Octet *)buf + ip_headerSize(buf);
}

static Uint32 ip_payloadSize(IP *buf) {
  // Return the IP payload size of a received packet, in Octets
  return ntohs(buf->ip.len) - ip_headerSize(buf);
}

void ip_register(Octet protocol, IPReceiver receiver);
// Register up-call handler for an IP protocol; NULL to disable.
//
// The handler will be called for incoming IP packets of its protocol,
// and also for incoming ICMP "error" packets that relate to its protocol.
// The handler can distinguish these through the IP "protocol" header field.
//
// The system registers an IPReceiver for ICMP, TCP, and UDP.

void ip_setSrce(IP *buf);
// Set srce address in buf, appropriately for dest address

void ip_send(IP *buf, Uint32 len, Octet ttl, Octet tos);
// Send an IP packet.  Protocol, versionAndLen, srce, and dest are set
// by caller.  "len" does not include the IP header


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// ARP                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

void arp_insert(IPAddr addr, MAC mac);
// Record an entry in the ARP cache

void arp_remove(IPAddr addr);
// Remove any existing entry for addr from the ARP cache


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// ICMP                                                                   //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define icmpTypeEchoReply 0
#define icmpTypeDestinationUnreachable 3
#define icmpTypeSourceQuench 4
#define icmpTypeRedirect 5
#define icmpTypeEchoRequest 8
#define icmpTypeTimeExceeded 11
#define icmpTypeParameterProblem 12
#define icmpTypeTimestamp 13
#define icmpTypeTimestampReply 14
#define icmpTypeInformationRequest 15
#define icmpTypeInformationReply 16

#define icmpCodeProtocolUnreachable 2
#define icmpCodePortUnreachable 3

#define icmpPayloadSize (68)

typedef struct ICMPHeader {
  Octet type;
  Octet code;
  Uint16 checksum;
  Uint32 misc;
} ICMPHeader;

typedef struct ICMP {          // ICMP packet for transmission (only)
  IPHeader ip;
  ICMPHeader icmp;
  Octet data[icmpPayloadSize]; // enough for maximum IP header plus 8 bytes
} ICMP;

typedef void (* ICMPReceiver)(IP *buf, Uint32 len);
// Up-call handler for received ICMP packets.
// len is the IP payload length (including ICMPHeader).

void icmp_register(Octet type, ICMPReceiver receiver);
// Register up-call handler for an ICMP type; NULL to disable.
//
// The handler will be called for incoming ICMP packets of its type,
// except for broadcasts, which are silently discarded.
//
// The system registers an ICMPReceiver for the types classed as "errors"
// by RFC 1122 (Destination Unreachable, Source Quench, Time Exceeded, and
// Parameter Problem).  That handler does ARP cache flushing, and passes the
// ICMP packet up to an appropriate transport layer receiver.  The system
// also handles Echo Request (by sending an Echo Reply).

void icmp_send(ICMP *buf, Uint32 len);
// Send ICMP packet in "buf".
// "len" is length of the ICMP payload (excluding ICMP header).
// Destination IP address, ICMP type, and ICMP code are set by caller.
//
// Basically, just sets the ICMP checksum and the remaining IP fields.

void icmp_bounce(IP *buf, int broadcast, Octet type, Octet code);
// Send an ICMP bounce in response to the given incoming packet.
//
// Overwrites "buf" (to avoid allocating its own).
// The bounce includes the IP header and 8 bytes of payload from "buf".
// Omits bounces prohibited by RFC 1122 (e.g. to broadcast addresses).


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// UDP                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

// Negative error codes for "len" in UDPReceiver up-calls or result of
// udp_recv.
//
#define udpRecvTimeout (-1)
#define udpRecvHostUnreachable (-2)
#define udpRecvPortUnreachable (-3)

typedef Uint16 UDPPort;       // UDP port, in hardware order

typedef struct UDPHeader {    // UDP header
  Uint16 srce;
  Uint16 dest;
  Uint16 len;                 // payload bytes + header bytes (8)
  Uint16 checksum;            // UDP checksum
} UDPHeader;

#define udpPayloadSize (ipPayloadSize - sizeof(UDPHeader))

typedef struct UDP {          // UDP packet for transmission (only)
  IPHeader ip;
  UDPHeader udp;
  Octet data[udpPayloadSize];
} UDP;

typedef void (* UDPReceiver)(IP *buf, int len, int broadcast,
           UDPPort dest);
// Up-call handler for received UDP packets to the port "dest".
// The buffer is available only during the up-call, and is NULL if
// len is negative.
//
// len is UDP payload length, or negative to report errors (not including
// timeout). "broadcast" is a boolean indicating packet was IP or
// link-level broadcast.

static Octet *udp_payload(IP *buf) {
  // Returns a pointer to the UDP payload area of a received packet.
  // Assumes a valid IP header length field.
  return ip_payload(buf) + sizeof(UDPHeader);
}

void udp_register(UDPPort p, UDPReceiver receiver);
// Note that a well-known UDPPort is in use, and register an up-call
// handler for it (or use udp_recv if receiver is NULL).
//
// Note than unlike lower layers, a NULL receiver doesn't mean "unregister";
// do that by calling udp_freePort.

UDPPort udp_allocPort(UDPReceiver receiver);
// Allocate an unused, dynamic UDP port number and register an up-call
// handler for it (or use udp_recv if receiver is NULL).

void udp_freePort(UDPPort p);
// Free a previously allocated dynamic or well-known UDP Port.
// Subsequent packets addressed to that port will be discarded (with an
// ICMP "Destination Unreachable" bounce, if appropriate).

int udp_recv(IP **buf, UDPPort p, Microsecs microsecs);
// If a port was provided with a NULL "receiver" call-back, an incoming
// packet is instead copied and queued, then made available to this
// blocking receive call.  The packet must eventually be freed by
// calling "udp_recvDone".
//
// On successful receive, the packet buffer is assigned to "buf" and the
// UDP payload length is returned.  On failure, NULL is assigned to "buf"
// and a negative error code is returned.

void udp_recvDone(IP *buf);
// Return a buffer acquired by "udp_recv".
// For convenience, accepts NULL (and does nothing).

void udp_send(UDP *buf, Uint32 len);
// Send UDP packet in "buf".
// "len" is length of the UDP payload (excluding header).
// Destination address and port and source port have been placed in header
// fields of "buf".  "udp_send" fills in source IP, checksums, etc.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// TCP                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define tcpConnectionDied (-1)
// Connection was abandoned because other end didn't respond to packets or
// responded with a RESET, or because this end aborted or closed the
// connection; can be returned by tcp_send or tcp_recv.  The connection is
// no longer usable, except for passing it to tcp_close.

typedef Uint16 TCPPort;      // TCP port number, in hardware order

typedef struct TCP * TCP;    // TCP connection handle

void tcp_listen(TCPPort localPort, IPAddr remoteAddr, TCPPort remotePort,
    int backlog);
// Configures the system to accept TCP connections to the given local port.
// If remoteAddr is non-zero, accepts connections only from that address;
// otherwise from any address.  If remotePort is non-zero, accepts
// connections only from that port; otherwise from any port.
//
// This call returns immediately.  Subsequently, the system will allow
// connections to be established.  The client can access those connections
// by calling "tcp_accept".  The parameter "backlog" is the number of
// connections that can be established in excess of the number of
// outstanding calls of tcp_accept.  Connection attempts beyond that number
// will be ignored (not rejected); the connecting system will presumably
// retransmit them for a while before timing out.
//
// Subsequent calls of tcp_listen for the same localPort override this one.
// A call with backlog < 0 disables the local port, reject all subsequent
// connection attempts.
//
// This provides the semantics of an unbounded set of calls of "passive
// open" in RFC 793, or the semantics of "listen" in the BSD socket
// interface.

TCP tcp_accept(TCPPort localPort, IPAddr *remoteAddr, TCPPort *remotePort,
         Microsecs microsecs);
// Block until there is an established connection to localPort, then return
// the connection.  Returns NULL if localPort is disabled, either by never
// having been provided to tcp_listen, or if its backlog is set to negative,
// or if no connection arrives within the given timeout.  Use microsecs=0
// for an infinite timeout.
//
// Assigns to *remoteAddr and *remotePort if they're non-null.
//
// This provides the result of "passive open" in RFC 793, or of "accept"
// in the BSD socket interface.

TCP tcp_connect(TCPPort localPort, IPAddr remoteAddr, TCPPort remotePort,
    Microsecs microsecs);
// Establish a TCP connection from localPort to the given (non-zero)
// remoteAddr and remotePort.  If localPort is 0, a dynamically allocated
// purt number is used.  Returns the connection, or NULL if the connection
// attempt fails (by the timeout expiring, by rejection from the other
// end).  Use microsecs==0 for an infinite timeout (but why?)
//
// This provides the semantics of "active open" in RFC 793, or of "connect"
// in the BSD socket interface.

int tcp_send(TCP tcp, Octet *buf, Uint32 len);
// Send the given data on the connection, asynchronously.
// Returns count of Octets consumed (always len), or a negative error code
// if the connection has failed or has been shutdown or aborted locally.
//
// The system will aggregate data provided by tcp_send until a convenient
// time to transmit it, in order to transmit full packets.  Use tcp_push to
// force transmission of a smaller packet.
//
// This will block indefinitely if the outbound stream is stopped
// because of flow control (meaning the other end isn't consuming data).
// It will terminate if the client calls tcp_abort.

void tcp_push(TCP tcp);
// Initiate transmission of data aggregated from previous calls of tcp_send,
// if any.  Does not wait for acknowledgement; the data will be
// retransmitted as necessary.

void tcp_shutdown(TCP tcp);
// Terminate the outbound data stream of the connection.  This transmits any
// pending data (as with tcp_push), then transmits an end-of-stream marker
// (FIN) on the stream; it does nothing if the stream is already terminated
// or the connection has failed.  Does not wait for acknowledgement; the
// FIN will be retransmitted as necessary.
//
// It is still possible to receive data from the inbound data stream of
// the connection.  For example, an HTTP 1.0 interaction involves the
// client opening a connection, sending the request data, calling
// tcp_shutdown, then reading the result data from the connection.
//
// This provides the semantics of "close" in RFC 793 (except for not waiting
// for acknowledgement), and the "SHUT_WR" semantics of "shutdown" in the
// BSD socket interface.  (I see no need for "SHUT_RD" in TCP.)

int tcp_recv(TCP tcp, Octet *buf, Uint32 len);
// Place inbound data in "buf", limited to "len" octets, and return the
// count of octets, or a negative code if the connection has failed or has
// been aborted locally.
//
// In general, this blocks until buf is filled.  It will return with
// less than "len" octets if the sender used the PUSH flag when sending
// the most recent byte of the data, or if an end-of-stream marker (FIN)
// is received.  It will return 0 iff there is no more data and an
// end-of-stream marker has been received.  It will terminate if the client
// calls tcp_abort.
//
// Note that a received PUSH flag, followed by more data before being
// reported through tcp_recv, will be ignored.  PUSH is not a record
// marker, and its delivery to the application is optional (RFC 1122).

void tcp_abort(TCP tcp);
// Discard any data waiting to be transmitted or acknowledged, and abandon
// any unread inbound data.  A "reset" indication will be sent to the other
// end.  Does not wait for a response, and does nothing if the connection
// has already failed.
//
// The client must nevertheless call tcp_close.
//
// This provides the semantics of "abort" in RFC 793.  In BSD sockets, this
// is "close" with linger set to false (0).

void tcp_close(TCP tcp);
// Terminate the connection.  This must be called, exactly once, for each
// TCP obtained from tcp_accept or tcp_connect.
//
// Unless tcp_abort has previously been called, this attempts a clean
// shutdown, using tcp_shutdown and waiting for the other end to
// acknowledge our end-of-stream marker (FIN).  If our FIN gets acknowledged
// but the other end hasn't sent its one, we send a "reset" indication (as
// in tcp_abort).
//
// Any further client use of "tcp" is prohibited.
//
// This has no direct equivalent in RFC 793, but matches (I believe) the
// default semantics of "close" in the BSD socket interface. 


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// DNS                                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define dnsNameTooLong (-1)
#define dnsNoServer (-2)
#define dnsTimeout (-3)
#define dnsMalformedQuery (-4)
#define dnsNameNotFound (-5)
#define dnsServerRefused (-6)
#define dnsNameHasNoAddress (-7)
#define dnsMalformedResponse (-8)

int dns_lookup(char *name, IPAddr *res);
// Assigns an IP address for domain name "name" *res, if available.
// Uses DNS server addresses obtained previously from DHCP.
// Returns 0 on success, error code on failure.
//
// Assumes the DNS server will handle recursive queries.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// TFTP                                                                   //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

char *tftp_get(IPAddr server, char *file,
         void(*receiver)(Octet *, Uint32));
// Fetch file from tftp server, using given IP address and file name.
// Contents are delivered by call-back to "receiver(buffer, length)".
// Returns null on successful completion, or error message string


#endif
