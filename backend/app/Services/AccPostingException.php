<?php

namespace App\Services;

/**
 * Raised when a posting request violates the document-cycle rules
 * (unbalanced entry, malformed line, unknown account, bad doc type).
 * Distinct from infrastructure failures so callers can tell a
 * client error from a transient DB problem.
 */
class AccPostingException extends \RuntimeException
{
}
