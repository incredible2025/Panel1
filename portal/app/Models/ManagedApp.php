<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ManagedApp extends Model
{
    protected $attributes = ['revision' => 0, 'draft_version' => 1];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['draft' => 'array', 'revision' => 'integer', 'draft_version' => 'integer'];
    }

    public function revisions(): HasMany
    {
        return $this->hasMany(ConfigRevision::class);
    }
}
