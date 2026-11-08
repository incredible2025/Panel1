package com.streamline.iptv

import org.junit.Assert.*
import org.junit.Test

class VlcVideoOutputTest {
    @Test fun initialSurfaceUsesRealPixelsBeforeMetadataArrives() {
        val buffers = mutableListOf<Pair<Int, Int>>()
        val output = VlcVideoOutput { w, h -> buffers.add(w to h) }
        output.initialise()
        assertEquals(listOf(1920 to 1080), buffers)
        assertNull(output.sourceSize)
    }

    @Test fun glOutputUsesTrackSizeWithoutAnyLayoutCallback() {
        val buffers = mutableListOf<Pair<Int, Int>>()
        val output = VlcVideoOutput { w, h -> buffers.add(w to h) }
        output.initialise()
        assertTrue(output.update(1280, 720))
        assertEquals(1280 to 720, buffers.last())
        assertEquals(VlcVideoSize(1280, 720), output.sourceSize)
    }

    @Test fun fullHdMetadataDoesNotResetAnAlreadyCorrectBuffer() {
        val buffers = mutableListOf<Pair<Int, Int>>()
        val output = VlcVideoOutput { w, h -> buffers.add(w to h) }
        output.initialise()
        assertTrue(output.update(1920, 1080))
        assertFalse(output.update(1920, 1080))
        assertEquals(listOf(1920 to 1080), buffers)
        assertEquals(VlcVideoSize(1920, 1080), output.sourceSize)
    }

    @Test fun adaptiveResolutionChangesKeepFullSourceResolution() {
        val buffers = mutableListOf<Pair<Int, Int>>()
        val output = VlcVideoOutput { w, h -> buffers.add(w to h) }
        output.initialise()
        output.update(3840, 2160)
        output.update(1280, 720)
        output.update(1280, 720)
        assertEquals(listOf(1920 to 1080, 3840 to 2160, 1280 to 720), buffers)
    }

    @Test fun missingMetadataCannotShrinkTheVideoSurface() {
        val output = VlcVideoOutput { _, _ -> }
        output.update(1920, 1080)
        assertFalse(output.update(0, 0))
        assertFalse(output.update(-1, 720))
        assertEquals(VlcVideoSize(1920, 1080), output.sourceSize)
    }

    @Test fun anamorphicTracksUseTheirDisplayAspectRatio() {
        val output = VlcVideoOutput { _, _ -> }
        output.update(720, 576, 16, 15)
        assertEquals(VlcVideoSize(768, 576), output.sourceSize)
        output.update(720, 576, 64, 45)
        assertEquals(VlcVideoSize(1024, 576), output.sourceSize)
    }

    @Test fun rotatedTracksSwapDisplayDimensions() {
        val output = VlcVideoOutput { _, _ -> }
        output.update(1920, 1080, rotated = true)
        assertEquals(VlcVideoSize(1080, 1920), output.sourceSize)
    }

    @Test fun invalidAspectRatioAndOversizedMetadataAreHandledSafely() {
        val output = VlcVideoOutput { _, _ -> }
        output.update(1920, 1080, 1, 0)
        assertEquals(VlcVideoSize(1920, 1080), output.sourceSize)
        assertFalse(output.update(1920, 1080, Int.MAX_VALUE, 1))
        assertFalse(output.update(Int.MAX_VALUE, Int.MAX_VALUE))
        assertEquals(VlcVideoSize(1920, 1080), output.sourceSize)
    }
}
