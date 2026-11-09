<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class PrivateResponses
{
    public function handle(Request $request, Closure $next): mixed
    {
        $response = $next($request);
        if (! $request->is('api/v1/apps/*/config')) {
            $response->headers->set('Cache-Control', 'private, no-store');
        }
        $response->headers->set('Referrer-Policy', 'no-referrer');
        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');

        return $response;
    }
}
