<?php

namespace App\Services;

use App\Models\ManagedApp;
use Carbon\Carbon;

class ConfigurationPreview
{
    public const FIELDS = [
        'primary' => 'Primary service address', 'fallback' => 'Fallback service address',
        'updateManifestUrl' => 'Update feed', 'noticeTitle' => 'Notice title',
        'noticeBody' => 'Notice message', 'noticeExpiresAt' => 'Notice expiry',
        'supportEmail' => 'Support email', 'supportWebsite' => 'Support website',
        'supportMessage' => 'Support message',
    ];

    public function changes(array $before, array $after): array
    {
        $result = [];
        foreach (self::FIELDS as $field => $label) {
            $old = (string) ($before[$field] ?? '');
            $new = (string) ($after[$field] ?? '');
            if ($field === 'noticeExpiresAt') {
                $old = $old ? Carbon::parse($old)->utc()->toIso8601String() : '';
                $new = $new ? Carbon::parse($new)->utc()->toIso8601String() : '';
            }
            if ($old !== $new) {
                $result[] = ['label' => $label, 'before' => $old, 'after' => $new];
            }
        }

        return $result;
    }

    public function describe(ManagedApp $app, ?array $candidate = null, ?string $serviceId = null): array
    {
        $published = $app->revisions()->where('revision', $app->revision)->first();

        return ['changes' => $this->changes($published?->configuration ?? [], $candidate ?? $app->draft),
            'signInRequired' => $published !== null && $published->service_id !== ($serviceId ?? $app->service_id),
            'firstPublication' => $published === null];
    }
}
