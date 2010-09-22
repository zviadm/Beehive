////////////////////////////////////////////////////////////////////////////
//                                                                        //
// tftp.c                                                                 //
//                                                                        //
// TFTP client                                                            //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "network.h"

// well-known server port
#define tftpPort 69

// tftp opcodes
#define tftpOpRRQ 1
#define tftpOpWRQ 2
#define tftpOpData 3
#define tftpOpAck 4
#define tftpOpError 5

// tftp packet layout
typedef struct TFTPHeader {
  short op;
  short block; // omitted for op=RRQ,WRQ; error number for op=Error
} TFTPHeader;
#define tftpPosName 2
#define tftpPosData 4

#define retryLimit 5    /* maximum number of transmission attempts */
#define timeout 3000000 /* receive timeout, in microseconds */

void appendStr(UDP *sendBuf, Uint32 *pos, char * str) {
  // Append null-terminated string to "sendBuf" at "pos", updating "pos"
  int i = 0;
  for (;;) {
    sendBuf->data[*pos] = (Octet)str[i];
    (*pos)++;
    if (str[i] == 0) break;
    i++;
  }
}

char * tftp_get(IPAddr server, char * file,
		void(*receiver)(Octet *, Uint32)) {
  UDP *sendBuf = (UDP *)enet_alloc();
  UDPPort local = udp_allocPort(NULL);
  sendBuf->ip.dest = hton(server);
  sendBuf->udp.dest = htons(tftpPort);
  sendBuf->udp.srce = htons(local);
  TFTPHeader * sendHeader = (TFTPHeader *)&(sendBuf->data[0]);
  sendHeader->op = htons(tftpOpRRQ);
  Uint32 pos = tftpPosName;
  appendStr(sendBuf, &pos, file);
  appendStr(sendBuf, &pos, "octet");
  Uint32 blockNum;
  for (blockNum = 1; ; blockNum++) {
    Uint32 recvLen;
    IP * recvBuf;
    TFTPHeader * recvHeader;
    Octet * recvData;
    Uint32 dataLen;
    int tries;
    for (tries = 0; ; tries++) {
      if (tries >= retryLimit) {
	udp_freePort(local);
	enet_free((Enet *)sendBuf);
	return "Timeout";
      }
      udp_send(sendBuf, pos);
      recvLen = udp_recv(&recvBuf, local, timeout);
      if (recvBuf) {
	recvHeader = (TFTPHeader *)udp_payload(recvBuf);
	recvData = udp_payload(recvBuf) + tftpPosData;
	dataLen = recvLen - tftpPosData;
	if (ntohs(recvHeader->op) == tftpOpData) {
	  if (ntohs(recvHeader->block) == blockNum) break;
	} else if (ntohs(recvHeader->op) == tftpOpError) {
	  recvData[dataLen-1] = 0; // in case server omitted it
	  udp_freePort(local);
	  enet_free((Enet *)sendBuf);
	  int slen = strlen((char *)recvData);
	  char *s = malloc(slen+1);
	  strncpy(s, (char *)recvData, slen+1);
	  udp_recvDone(recvBuf);
	  return s;
	} else {
	  udp_freePort(local);
	  enet_free((Enet *)sendBuf);
	  udp_recvDone(recvBuf);
	  return "Unknown opcode from server";
	}
	// ignore other stuff - excess retransmissions
	udp_recvDone(recvBuf);
      }
    }
    // The only way to get here is by receiving the expected data block
    receiver(recvData, dataLen);
    UDPHeader *recvUDPHeader = (UDPHeader *)ip_payload(recvBuf);
    sendBuf->udp.dest = recvUDPHeader->srce;
    sendHeader->op = htons(tftpOpAck);
    sendHeader->block = recvHeader->block;
    pos = tftpPosData;
    udp_recvDone(recvBuf);
    if (dataLen < 512) break;
  }
  udp_send(sendBuf, pos); // final ACK, sent without retransmissions
  udp_freePort(local);
  enet_free((Enet *)sendBuf);
  return NULL;
}
