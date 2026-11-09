<?php

namespace App\Http\Controllers;

use App\Models\ManagedApp;
use Illuminate\Http\Request;

class PublicConfigController extends Controller
{
    public function __invoke(Request $request, string $appId)
    {
        $app = ManagedApp::where('app_id', $appId)->firstOrFail();
        $revision = $app->revisions()->where('revision', $app->revision)->firstOrFail();
        $response = response()->json($revision->envelope())
            ->setEtag(hash('sha256', $revision->payload))
            ->header('Cache-Control', 'public, no-cache, must-revalidate')
            ->header('X-Content-Type-Options', 'nosniff');
        $response->isNotModified($request);

        return $response;
    }
}
