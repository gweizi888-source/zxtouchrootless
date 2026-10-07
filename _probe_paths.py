import paramiko

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.0.101", username="mobile", password="12345678", timeout=8, allow_agent=False, look_for_keys=False)
cmd = r"""
echo '=== scripts real ==='
ls -la /var/mobile/Library/ZXTouch/scripts 2>/dev/null | head -50
echo '=== jbroot dirs ==='
ls -d /var/containers/Bundle/Application/.jbroot-* /private/var/containers/Bundle/Application/.jbroot-* 2>/dev/null
echo '=== jbroot zxtouch ==='
for d in /var/containers/Bundle/Application/.jbroot-* /private/var/containers/Bundle/Application/.jbroot-*; do
  [ -d "$d" ] || continue
  echo "-- $d"
  ls -ld "$d/var/mobile/Library/ZXTouch" "$d/var/mobile/Library/ZXTouch/scripts" 2>/dev/null
  ls "$d/var/mobile/Library/ZXTouch/scripts" 2>/dev/null | head
done
echo '=== log tail ==='
tail -c 3000 /var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/output 2>/dev/null
echo
echo '=== find ZXTouch scripts dirs ==='
find /var/containers /private/var/containers /var/jb /private/preboot -type d -path '*ZXTouch/scripts' 2>/dev/null | head -30
"""
stdin, stdout, stderr = c.exec_command(cmd, timeout=40)
print(stdout.read().decode("utf-8", "replace"))
err = stderr.read().decode("utf-8", "replace")
if err.strip():
    print("STDERR", err[:3000])
c.close()
