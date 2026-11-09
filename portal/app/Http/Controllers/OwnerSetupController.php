<?php

namespace App\Http\Controllers;

use App\Services\OwnerInvitation;
use Illuminate\Http\Request;
use Illuminate\Validation\Rules\Password;

class OwnerSetupController extends Controller
{
    public function show(string $token, OwnerInvitation $invitation)
    {
        abort_unless($invitation->valid($token), 404);

        return response()->view('management.setup', ['token' => $token])->header('Cache-Control', 'no-store')->header('Referrer-Policy', 'no-referrer');
    }

    public function store(Request $request, string $token, OwnerInvitation $invitation)
    {
        abort_unless($invitation->valid($token), 404);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'email' => ['required', 'email', 'max:255', 'unique:users'],
            'password' => ['required', 'confirmed', Password::min(14)->letters()->numbers()],
        ]);
        $invitation->accept($token, $data);

        return redirect()->route('login')->with('status', 'Owner account created. Sign in to manage your apps.');
    }
}
