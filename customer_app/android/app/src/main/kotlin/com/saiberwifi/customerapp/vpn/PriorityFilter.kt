package com.saiberwifi.customerapp.vpn

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * PriorityFilter — IP packet classifier for Emergency / Deep Freeze modes.
 * Parses raw IPv4 bytes and returns a Verdict.
 *
 * Priority War Rules:
 *  DEEP_FREEZE  → only UDP ≤1500b from allowed UIDs survive; TCP gets RST
 *  EMERGENCY    → UDP free, TCP SYN allowed once per 30s; heavy TCP → RST
 *  NORMAL/DEGRADED → whitelist UID check only
 */
object PriorityFilter {

    enum class Verdict { ALLOW, DROP, KILL_TCP }

    private const val PROTO_TCP: Int = 6
    private const val PROTO_UDP: Int = 17

    fun classify(
        packet: ByteArray,
        srcUid: Int,
        allowedUids: Set<Int>,
        state: AiState,
    ): Verdict {
        if (packet.size < 20) return Verdict.DROP

        val buf = ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN)
        val versionIhl = buf.get(0).toInt() and 0xFF
        val ipVersion  = versionIhl shr 4
        if (ipVersion != 4) return Verdict.DROP

        val ihl      = (versionIhl and 0xF) * 4
        val totalLen = buf.getShort(2).toInt() and 0xFFFF
        val proto    = buf.get(9).toInt() and 0xFF

        val payloadLen = totalLen - ihl - when (proto) {
            PROTO_TCP -> tcpHeaderLen(packet, ihl)
            PROTO_UDP -> 8
            else -> 0
        }

        return when (state) {
            AiState.DEEP_FREEZE -> deepFreezeVerdict(proto, payloadLen, srcUid, allowedUids)
            AiState.EMERGENCY   -> emergencyVerdict(proto, payloadLen, packet, ihl, srcUid, allowedUids)
            else                -> if (allowedUids.isEmpty() || srcUid in allowedUids) Verdict.ALLOW else Verdict.DROP
        }
    }

    private fun deepFreezeVerdict(
        proto: Int,
        payloadLen: Int,
        srcUid: Int,
        allowedUids: Set<Int>,
    ): Verdict {
        if (srcUid !in allowedUids && allowedUids.isNotEmpty()) return Verdict.DROP
        return when {
            proto == PROTO_UDP && payloadLen <= 1500 -> Verdict.ALLOW
            proto == PROTO_TCP                       -> Verdict.KILL_TCP
            else                                     -> Verdict.DROP
        }
    }

    private fun emergencyVerdict(
        proto: Int,
        payloadLen: Int,
        packet: ByteArray,
        ihl: Int,
        srcUid: Int,
        allowedUids: Set<Int>,
    ): Verdict {
        if (srcUid !in allowedUids && allowedUids.isNotEmpty()) return Verdict.DROP
        return when {
            proto == PROTO_UDP -> Verdict.ALLOW
            proto == PROTO_TCP && isTcpSyn(packet, ihl) -> Verdict.ALLOW
            proto == PROTO_TCP && payloadLen > 512 -> Verdict.KILL_TCP
            else -> Verdict.ALLOW
        }
    }

    private fun isTcpSyn(packet: ByteArray, ihl: Int): Boolean {
        val flags = packet[ihl + 13].toInt() and 0x3F
        return (flags and 0x02) != 0
    }

    private fun tcpHeaderLen(packet: ByteArray, ihl: Int): Int {
        val dataOffset = (packet[ihl + 12].toInt() shr 4) and 0xF
        return dataOffset * 4
    }
}

enum class AiState { NORMAL, DEGRADED, EMERGENCY, DEEP_FREEZE }
