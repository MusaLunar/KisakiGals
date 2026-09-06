import os
import zipfile

out = 'dist/KisakiGals-0.9.0-beta-portable.zip'
app = 'stage_pkg/app'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write('README.md', 'KisakiGals/README.md')
    for root, _, fs in os.walk(app):
        for f in fs:
            full = os.path.join(root, f)
            arc = 'KisakiGals/' + os.path.relpath(full, app).replace(os.sep, '/')
            z.write(full, arc)
print(out, os.path.getsize(out) // 1024 // 1024, 'MB')
