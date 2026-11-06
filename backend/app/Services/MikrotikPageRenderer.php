<?php

namespace App\Services;

use Illuminate\Support\Str;
use Illuminate\Support\Facades\File;

/**
 * Renders hotspot login-page templates into per-request folders the
 * router can pull with `/tool/fetch` — no FTP needed.
 *
 * Template sources live in resources/mikrotik-pages/{id}/ and use
 * {{placeholder}} tokens; RouterOS's own $(var) syntax passes through
 * untouched. Shared assets (status/logout/md5.js) come from _shared/.
 */
class MikrotikPageRenderer
{
    private const SOURCE_DIR = 'resources/mikrotik-pages';
    private const RENDER_DIR = 'mikrotik-pages';
    private const TTL_HOURS = 24;

    /** Files every render produces (login.html is per-template). */
    private const SHARED_FILES = ['status.html', 'logout.html', 'md5.js'];

    /** All templates with their manifests. */
    public function templates(): array
    {
        $out = [];
        foreach (File::directories(base_path(self::SOURCE_DIR)) as $dir) {
            $manifest = $dir . '/template.json';
            if (!File::exists($manifest)) {
                continue;
            }
            $meta = json_decode(File::get($manifest), true) ?: [];
            $out[] = [
                'id' => basename($dir),
                'name' => $meta['name'] ?? basename($dir),
                'description' => $meta['description'] ?? '',
                'premium' => (bool) ($meta['premium'] ?? false),
                'defaults' => $meta['defaults'] ?? [],
            ];
        }
        return $out;
    }

    public function exists(string $id): bool
    {
        return File::exists(
            base_path(self::SOURCE_DIR . "/{$id}/template.json"));
    }

    /** Premium templates require a paid (active) subscription. */
    public function isPremium(string $id): bool
    {
        $manifest = base_path(self::SOURCE_DIR . "/{$id}/template.json");
        if (!File::exists($manifest)) {
            return false;
        }
        $meta = json_decode(File::get($manifest), true) ?: [];
        return (bool) ($meta['premium'] ?? false);
    }

    /**
     * Render a template with the owner's customization and write the
     * file set to storage/app/mikrotik-pages/{renderId}/.
     *
     * @return array{render_id:string, files:list<array{name:string,path:string}>}
     */
    public function render(string $id, array $vars, ?string $logoDataUri = null): array
    {
        $this->cleanup();

        $renderId = (string) Str::ulid();
        $outDir = storage_path('app/' . self::RENDER_DIR . '/' . $renderId);
        File::ensureDirectoryExists($outDir);

        $replace = [
            '{{network_name}}' => e($vars['network_name'] ?? 'شبكتي'),
            '{{welcome_msg}}' => e($vars['welcome_msg'] ?? ''),
            '{{whatsapp}}' => e($vars['whatsapp'] ?? ''),
            '{{speed_label}}' => e($vars['speed_label'] ?? ''),
            '{{color_primary}}' => e($vars['color_primary'] ?? '#1a3a6b'),
            '{{color_accent}}' => e($vars['color_accent'] ?? '#c8102e'),
            '{{logo}}' => $logoDataUri
                ? '<img class="logo" src="' . $logoDataUri . '" alt="">'
                : '',
            '{{support_line}}' => !empty($vars['whatsapp'])
                ? 'للدعم الفني: <a href="tel:' . e($vars['whatsapp']) . '">'
                    . e($vars['whatsapp']) . '</a>'
                : '{{network_name}}',
            '{{year}}' => date('Y'),
        ];
        // support_line can't contain the literal placeholder.
        $replace['{{support_line}}'] = str_replace(
            '{{network_name}}', $replace['{{network_name}}'],
            $replace['{{support_line}}']);

        $files = [];

        // Per-template login page.
        $login = File::get(base_path(self::SOURCE_DIR . "/{$id}/login.html"));
        $files[] = $this->write($outDir, 'login.html', $login, $replace);

        // Browser-friendly preview: RouterOS $(var) tokens resolved to
        // sample values so the owner sees the real design, not raw
        // template code. Router files (login.html) keep $(...) intact.
        File::put("{$outDir}/preview.html",
            $this->previewHtml(strtr($login, $replace)));

        // Shared pages (status/logout/md5) styled with the same vars.
        foreach (self::SHARED_FILES as $name) {
            $src = base_path(self::SOURCE_DIR . "/_shared/{$name}");
            $files[] = $this->write($outDir, $name,
                File::get($src), $replace);
        }

        return ['render_id' => $renderId, 'files' => $files];
    }

    /**
     * Resolve RouterOS $(var) tokens to sample values for the in-app
     * preview: $(if ...)/$(endif) markers are stripped so conditional
     * sections stay visible, the error block is hidden, and remaining
     * tokens get realistic placeholders.
     */
    private function previewHtml(string $html): string
    {
        // Drop the error-only block first — no error in a preview.
        $html = preg_replace(
            '/\$\(\s*if\s+error\s*\).*?\$\(\s*endif\s*\)/s', '', $html);
        // Keep the content of other conditional sections.
        $html = preg_replace(
            '/\$\(\s*if\s+[^)]*\)|\$\(\s*endif\s*\)/', '', $html);
        $samples = [
            'username' => 'CARD-1234',
            'password' => '',
            'link-login-only' => '#',
            'link-orig' => '#',
            'link-orig-esc' => '#',
            'link-status' => '#',
            'link-logout' => '#',
            'mac' => '00:11:22:33:44:55',
            'mac-esc' => '001122334455',
            'ip' => '10.5.50.2',
            'chap-id' => '',
            'chap-challenge' => '',
            'trial' => 'yes',
            'error' => '',
            'error-orig' => '',
            'hostname' => 'mikrotik',
            'uptime' => '1h 23m',
            'bytes-in-nice' => '12 MB',
            'bytes-out-nice' => '48 MB',
            'session-time-left' => '',
        ];
        return preg_replace_callback(
            '/\$\(([A-Za-z0-9-]+)\)/',
            fn(array $m) => $samples[$m[1]] ?? '',
            $html) ?? $html;
    }

    private function write(string $dir, string $name, string $content,
                           array $replace): array
    {
        $content = strtr($content, $replace);
        File::put("{$dir}/{$name}", $content);
        return ['name' => $name, 'path' => "{$dir}/{$name}"];
    }

    /** Absolute path for a rendered file, or null when invalid. */
    public function filePath(string $renderId, string $file): ?string
    {
        if (!preg_match('/^[A-Za-z0-9]{10,40}$/', $renderId)
            || !preg_match('/^[a-zA-Z0-9_-]+\.(html|js|css|png|svg)$/', $file)) {
            return null;
        }
        $path = storage_path('app/' . self::RENDER_DIR
            . "/{$renderId}/{$file}");
        return File::exists($path) ? $path : null;
    }

    /** Drop render folders older than TTL — best effort per request. */
    private function cleanup(): void
    {
        $root = storage_path('app/' . self::RENDER_DIR);
        if (!File::isDirectory($root)) {
            return;
        }
        $cutoff = now()->subHours(self::TTL_HOURS)->getTimestamp();
        foreach (File::directories($root) as $dir) {
            if (File::lastModified($dir) < $cutoff) {
                File::deleteDirectory($dir);
            }
        }
    }
}
