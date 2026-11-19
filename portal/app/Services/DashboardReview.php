<?php

namespace App\Services;

use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class DashboardReview
{
    public function store(Request $request, string $kind, array $data): string
    {
        $ticket = (string) Str::uuid();
        $request->session()->put('management.reviews.'.$ticket, [
            'actor' => $request->user()->id, 'expires' => now()->addMinutes(15)->timestamp,
            'kind' => $kind, 'data' => $data,
        ]);

        return $ticket;
    }

    public function get(Request $request, string $ticket): array
    {
        $plan = $request->session()->get('management.reviews.'.$ticket);
        if (! is_array($plan) || $plan['actor'] !== $request->user()->id || $plan['expires'] < now()->timestamp) {
            throw ValidationException::withMessages(['review' => 'This review has expired. Start a fresh review before applying changes.']);
        }

        return $plan;
    }

    public function forget(Request $request, string $ticket): void
    {
        $request->session()->forget('management.reviews.'.$ticket);
    }
}
