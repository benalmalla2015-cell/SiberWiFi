<?php

namespace App\Services;

use App\Models\CyberSubscriber;

/**
 * Issuer of the subscriber's EAP-TLS certificate identity (CYB-01 engine).
 *
 * Implementations are swappable: while the engine is unavailable the
 * CyberCertificateIssuerStub keeps identities in 'pending'. When CYB-01
 * lands, the real implementation gets bound to this interface (e.g. in
 * CyberServiceProvider) and is injected automatically — no change to the
 * registration flow.
 */
interface CyberCertificateIssuer
{
    /**
     * Issue (or schedule issuance of) a certificate for the subscriber.
     *
     * @return array{certificate_serial: ?string, status: string}
     *         status is one of: pending|issued|active|revoked
     */
    public function issue(CyberSubscriber $subscriber, ?string $deviceId): array;
}
