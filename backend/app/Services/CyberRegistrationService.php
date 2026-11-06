<?php

namespace App\Services;

use App\Models\CyberSubscriber;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Client registration flow (CYB-03): persist the subscriber with a unique
 * 74XXXXXXX SIM number, store identity documents on the private disk, and
 * create the pending certificate identity via the swappable issuer.
 */
class CyberRegistrationService
{
    /**
     * The issuer is nullable on purpose: the container injects whatever is
     * bound to CyberCertificateIssuer (the real CYB-01 engine once ready);
     * until then the stub is used. Nothing here changes when it is swapped.
     */
    public function __construct(
        private CyberSimService $sim,
        private ?CyberCertificateIssuer $issuer = null,
    ) {
        $this->issuer ??= new CyberCertificateIssuerStub;
    }

    public function register(array $data, UploadedFile $front, ?UploadedFile $back = null): CyberSubscriber
    {
        $subscriber = $this->sim->withUniqueSim(
            fn (string $simNo) => DB::transaction(
                fn () => $this->persist($simNo, $data, $front, $back)
            )
        );

        $this->issueIdentity($subscriber);

        return $subscriber->load(['documents', 'identity']);
    }

    public function findBySim(string $simNo): ?CyberSubscriber
    {
        return CyberSubscriber::with(['documents', 'identity'])
            ->where('sim_no', $simNo)
            ->first();
    }

    private function persist(string $simNo, array $data, UploadedFile $front, ?UploadedFile $back): CyberSubscriber
    {
        $subscriber = CyberSubscriber::create([
            'sim_no' => $simNo,
            'full_name' => $data['full_name'],
            'directorate_id' => $data['directorate_id'],
            'sub_directorate_id' => $data['sub_directorate_id'],
            'status' => 'pending',
        ]);

        $dir = "cyber/documents/{$subscriber->id}";
        $subscriber->documents()->create([
            'document_type' => $data['document_type'],
            'front_path' => $front->store($dir, 'local'),
            'back_path' => $back?->store($dir, 'local'),
            'review_status' => 'pending',
        ]);

        $subscriber->identity()->create([
            'device_id' => $data['device_id'] ?? null,
            'status' => 'pending',
        ]);

        return $subscriber;
    }

    /**
     * Isolated certificate-issuance call. Runs after commit so an engine
     * outage never fails a completed registration — the identity simply
     * stays 'pending' for later re-issue.
     */
    private function issueIdentity(CyberSubscriber $subscriber): void
    {
        try {
            $result = $this->issuer->issue($subscriber, $subscriber->identity?->device_id);
        } catch (Throwable $e) {
            Log::warning('CyberNet certificate issuance deferred', [
                'subscriber_id' => $subscriber->id,
                'error' => $e->getMessage(),
            ]);

            return;
        }

        if (! empty($result['certificate_serial']) || ($result['status'] ?? 'pending') !== 'pending') {
            $subscriber->identity?->update([
                'certificate_serial' => $result['certificate_serial'] ?? null,
                'status' => $result['status'] ?? 'pending',
            ]);
        }
    }
}
