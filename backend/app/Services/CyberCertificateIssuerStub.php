<?php

namespace App\Services;

use App\Models\CyberSubscriber;

/**
 * No-op issuer used until the CYB-01 certificate engine is ready.
 * Every identity stays 'pending' with no serial; a later task replaces
 * this by binding a real CyberCertificateIssuer implementation.
 */
class CyberCertificateIssuerStub implements CyberCertificateIssuer
{
    public function issue(CyberSubscriber $subscriber, ?string $deviceId): array
    {
        return [
            'certificate_serial' => null,
            'status' => 'pending',
        ];
    }
}
