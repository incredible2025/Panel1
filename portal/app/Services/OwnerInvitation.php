<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class OwnerInvitation
{
    public function path(): string
    {
        return storage_path('app/private/owner-invitation.json');
    }

    public function valid(string $token): bool
    {
        if (User::where('role', 'owner')->exists() || ! is_file($this->path())) {
            return false;
        }
        $data = json_decode(file_get_contents($this->path()), true);

        return is_array($data) && ($data['expires'] ?? 0) > time()
            && hash_equals($data['hash'] ?? '', hash('sha256', $token));
    }

    public function accept(string $token, array $data): void
    {
        $lock = fopen($this->path().'.lock', 'c');
        if (! $lock || ! flock($lock, LOCK_EX)) {
            abort(503);
        }
        try {
            abort_unless($this->valid($token), 404);
            DB::transaction(function () use ($data) {
                abort_if(User::where('role', 'owner')->exists(), 404);
                $user = new User($data);
                $user->role = 'owner';
                $user->email_verified_at = now();
                $user->save();
            });
            unlink($this->path());
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }
}
