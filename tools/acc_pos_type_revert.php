<?php
$u = App\Models\User::where("phone","700000090")->firstOrFail();
$u->type = "client";
$u->save();
echo "reverted user=".$u->id." type=".$u->type.PHP_EOL;
