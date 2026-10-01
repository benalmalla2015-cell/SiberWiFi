package com.saiberwifi.customerapp.vpn

import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * PacketSurgeon — forges a TCP RST to instantly kill heavy connections.
 * When a browser or Play Services tries to open a page on a very slow line,
 * we RST it so the app stops retrying and wastes no more bandwidth.
 */
object PacketSurgeon {

    /**
     * Writes a forged RST reply to the VPN output stream.
     * The original packet must be an IPv4/TCP packet.
     */
    fun killTcp(originalPacket: ByteArray, vpnOutput: FileOutputStream) {
        if (originalPacket.size < 40) return
        val versionIhl = originalPacket[0].toInt() and 0xFF
        val ihl = (versionIhl and 0xF) * 4
        if (ihl < 20) return

        // Build minimal IPv4 + TCP RST packet (ihl + 20 bytes)
        val rst = ByteArray(ihl + 20)
        System.arraycopy(originalPacket, 0, rst, 0, minOf(ihl + 20, originalPacket.size))

        val buf = ByteBuffer.wrap(rst).order(ByteOrder.BIG_ENDIAN)

        // IPv4: total length = ihl + 20
        buf.putShort(2, (ihl + 20).toShort())
        // TTL = 64
        rst[8] = 64
        // Protocol stays TCP (6)

        // Swap src/dst IP
        for (i in 0 until 4) {
            val tmp = rst[12 + i]
            rst[12 + i] = rst[16 + i]
            rst[16 + i] = tmp
        }

        // Swap src/dst port
        val srcPort  = buf.getShort(ihl)
        val dstPort  = buf.getShort(ihl + 2)
        buf.putShort(ihl,     dstPort)
        buf.putShort(ihl + 2, srcPort)

        // Set SEQ = original ACK
        val ackNum = buf.getInt(ihl + 8)
        buf.putInt(ihl + 4, ackNum)     // SEQ = original ACK
        buf.putInt(ihl + 8, 0)          // ACK = 0

        // TCP flags = RST (0x04) + ACK (0x10)
        rst[ihl + 13] = 0x14.toByte()

        // Data offset = 5 (20 byte header, no options)
        rst[ihl + 12] = 0x50.toByte()

        // Window = 0
        buf.putShort(ihl + 14, 0)

        // Checksum = 0 (recompute)
        buf.putShort(ihl + 16, 0)

        // Clear IP checksum, recompute
        buf.putShort(10, 0)
        buf.putShort(10, ipChecksum(rst, ihl))

        // Compute TCP checksum
        buf.putShort(ihl + 16, tcpChecksum(rst, ihl))

        try {
            vpnOutput.write(rst)
        } catch (_: Exception) {}
    }

    private fun ipChecksum(packet: ByteArray, headerLen: Int): Short {
        var sum = 0
        var i = 0
        while (i < headerLen) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.inv() and 0xFFFF).toShort()
    }

    private fun tcpChecksum(packet: ByteArray, ihl: Int): Short {
        val srcIp  = ByteBuffer.wrap(packet, 12, 4).int
        val dstIp  = ByteBuffer.wrap(packet, 16, 4).int
        val tcpLen = 20 // RST has no data

        var sum = 0
        // Pseudo-header
        sum += (srcIp ushr 16) and 0xFFFF
        sum += srcIp and 0xFFFF
        sum += (dstIp ushr 16) and 0xFFFF
        sum += dstIp and 0xFFFF
        sum += 6       // TCP protocol
        sum += tcpLen

        // TCP header (20 bytes)
        var i = ihl
        while (i < ihl + tcpLen) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or
                   if (i + 1 < packet.size) packet[i + 1].toInt() and 0xFF else 0
            i += 2
        }
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.inv() and 0xFFFF).toShort()
    }
}
