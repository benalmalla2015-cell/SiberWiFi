<?php
$path = '/home/u170359695/domains/saiberwifi.net/public_html/backend/app/Http/Controllers/Api/AuthController.php';
$content = file_get_contents($path);

$old = <<<'PHP'
        $validator = Validator::make($request->all(), [
            'name'                  => 'required|string|max:255',
            'phone'                 => 'required|string|unique:users,phone|max:20',
            'password'              => 'required|string|min:6|confirmed',
            'region_id'             => 'required|exists:regions,id',
            'directorate_id'        => 'required|exists:directorates,id',
            'sub_directorate_id'    => 'required|exists:sub_directorates,id',
            'device_id'             => 'required|string|max:191|unique:users,device_id',
            'password_confirmation' => 'required',
        ]);
PHP;

$new = <<<'PHP'
        $validator = Validator::make($request->all(), [
            'name'                  => 'required|string|max:255',
            'phone'                 => 'required|string|unique:users,phone|max:20',
            'password'              => 'required|string|min:6|confirmed',
            'region_id'             => 'required|exists:regions,id',
            'directorate_id'        => 'required|exists:directorates,id',
            'sub_directorate_id'    => 'required|exists:sub_directorates,id',
            'device_id'             => 'required|string|max:191|unique:users,device_id',
            'password_confirmation' => 'required',
        ], [
            'device_id.required' => 'معرّف الجهاز مطلوب',
            'device_id.unique'   => 'هذا الجهاز مرتبط بحساب آخر',
        ]);
PHP;

if (strpos($content, $old) === false) {
    echo "Old pattern not found";
    exit(1);
}

$content = str_replace($old, $new, $content);
file_put_contents($path, $content);
echo "Patched device validation message";
