<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class ActiveStaff
{
    public function handle(Request $request, Closure $next): mixed
    {
        if ($request->user() && (! $request->user()->active || ! in_array($request->user()->role, ['owner', 'staff'], true))) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();
            abort(403);
        }

        return $next($request);
    }
}
