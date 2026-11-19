<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppDevice extends Model
{
    public $timestamps = false;

    protected $guarded = ['id'];

    protected $hidden = ['secret_hash', 'pair_hash'];

    protected function casts(): array
    {
        return ['last_seen_at' => 'datetime', 'pair_expires_at' => 'datetime', 'tester' => 'boolean'];
    }
}
