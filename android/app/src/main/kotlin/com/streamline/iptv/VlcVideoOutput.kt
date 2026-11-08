package com.streamline.iptv

internal data class VlcVideoSize(val width: Int, val height: Int)

/** Pixel dimensions for the native texture, independent of Flutter's layout. */
internal class VlcVideoOutput(private val resize: (Int, Int) -> Unit) {
    private var output = VlcVideoSize(1920, 1080)
    var sourceSize: VlcVideoSize? = null
        private set

    fun initialise() = resize(output.width, output.height)

    fun update(width: Int, height: Int, sarNum: Int = 1, sarDen: Int = 1, rotated: Boolean = false): Boolean {
        if (width !in 1..8192 || height !in 1..8192) return false
        val numerator = if (sarNum > 0 && sarDen > 0) sarNum.toLong() else 1L
        val denominator = if (sarNum > 0 && sarDen > 0) sarDen.toLong() else 1L
        val squarePixelWidth = (width.toLong() * numerator + denominator / 2) / denominator
        if (squarePixelWidth !in 1L..8192L) return false
        val next = if (rotated) VlcVideoSize(height, squarePixelWidth.toInt())
            else VlcVideoSize(squarePixelWidth.toInt(), height)
        val changed = next != sourceSize
        if (next != output) {
            resize(next.width, next.height)
            output = next
        }
        sourceSize = next
        return changed
    }
}
