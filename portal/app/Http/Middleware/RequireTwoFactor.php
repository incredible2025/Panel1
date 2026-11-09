<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class RequireTwoFactor
{
    public function handle(Request $request, Closure $next): mixed
    {
        if (config('management.require_two_factor') && (! $request->user()?->two_factor_secret || ! $request->user()?->two_factor_confirmed_at)) {
            return redirect()->route('security.edit')->with('status', 'Set up two-factor authentication to manage apps.');
        }

        return $next($request);
    }
}
