<?php
$u = App\Models\User::where("phone","700000090")->firstOrFail();
$u->type = "network_owner";
$u->save();
echo "flipped user=".$u->id." type=".$u->type.PHP_EOL;
