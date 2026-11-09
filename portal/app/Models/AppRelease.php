<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AppRelease extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    public function app(): BelongsTo
    {
        return $this->belongsTo(ManagedApp::class, 'managed_app_id');
    }

    protected function casts(): array
    {
        return ['manifest' => 'array', 'tested_at' => 'datetime', 'review_version' => 'integer'];
    }
}
