<?php

namespace App\Services;

class PlaybackGuidance
{
    /** @param array<string, mixed> $details
     * @return array{confidence: string, explanation: string, action: string}
     */
    public static function describe(string $category, array $details): array
    {
        $status = $details['http_status'] ?? null;
        if (is_int($status)) {
            return ['confidence' => str_starts_with($details['native_code'] ?? '', 'ERROR_CODE_') ? 'Confirmed observation' : 'Player-reported observation', 'explanation' => 'The player reported HTTP '.$status.'.',
                'action' => match (true) {
                    in_array($status, [401, 403], true) => 'Ask the service administrator to check account access and connection limits. The status alone does not identify the server rule that rejected the request.',
                    in_array($status, [404, 410], true) => 'Check whether this channel or replay is still available. Compare another title using the same account.',
                    $status >= 500 => 'Retry another channel and ask the service administrator to check server availability.',
                    default => 'Run connection diagnosis from the affected device and compare another channel.',
                }];
        }
        $cause = $details['cause'] ?? 'unknown';
        $native = $details['native_code'] ?? '';
        if (in_array($native, ['JAVA_OUT_OF_MEMORY', 'JAVA_ILLEGAL_STATE', 'JAVA_LINKAGE', 'JAVA_UNCAUGHT_EXCEPTION'], true)) {
            return ['confidence' => 'Confirmed observation', 'explanation' => match ($native) {
                'JAVA_OUT_OF_MEMORY' => 'An uncaught Android out-of-memory error occurred while playback was active.',
                'JAVA_LINKAGE' => 'An uncaught Android native-library linkage error occurred while playback was active.',
                'JAVA_ILLEGAL_STATE' => 'An uncaught Android illegal-state exception occurred while playback was active.',
                default => 'An uncaught Android exception occurred while playback was active.',
            }, 'action' => 'Compare the device, player and app version with other reports. For memory errors, compare a lower-resolution stream and hardware decoding. The context alone does not prove the player caused the crash.'];
        }
        $confirmed = is_string($native) && str_starts_with($native, 'ERROR_CODE_');
        if ($cause === 'decoder' || $cause === 'format') {
            return ['confidence' => $confirmed ? 'Confirmed observation' : 'Likely cause',
                'explanation' => $cause === 'decoder' ? 'The player reported a decoder or codec failure.' : 'The player could not read the media format.',
                'action' => 'Check the codec and actual decoder below, then compare another player or software decoding. Record whether the alternative restores playback.'];
        }
        if (in_array($cause, ['dns', 'tls', 'timeout', 'connection'], true)) {
            return ['confidence' => $confirmed ? 'Confirmed observation' : 'Likely cause',
                'explanation' => match ($cause) {
                    'dns' => 'The player could not resolve the service hostname.', 'tls' => 'Secure connection verification failed.', 'timeout' => 'The player reported a timeout.', default => 'The player reported a connection failure.'
                },
                'action' => 'Ask the customer to run and send connection diagnosis on this device. Compare its DNS, connection and account checks. A timeout alone does not identify ISP blocking.'];
        }
        if ($category === 'buffering' && ($details['buffer_ms'] ?? 0) >= 5000 && ($details['dropped_frames'] ?? 0) >= 30) {
            return ['confidence' => 'Likely cause', 'explanation' => 'The player reported buffered media and substantial frame dropping.',
                'action' => 'Compare decoding modes and a lower-resolution stream. The observations suggest a decoding or rendering bottleneck; they do not establish its exact cause.'];
        }
        if (in_array($category, ['green_screen', 'no_picture', 'pixelation'], true)) {
            return ['confidence' => 'User observation', 'explanation' => PlaybackReports::CATEGORIES[$category].'.',
                'action' => 'Compare the same content in another player. Review video codec, actual decoder and dropped frames before changing defaults for this device.'];
        }

        return ['confidence' => 'Undetermined', 'explanation' => $category === 'buffering' ? 'The player reported prolonged buffering.' : 'The received report does not identify a specific root cause.',
            'action' => 'Open the session timeline and check recovery results. Ask the customer to send connection diagnosis using the support reference. New reports can include technical details after the app is updated; older reports remain unchanged.'];
    }
}
