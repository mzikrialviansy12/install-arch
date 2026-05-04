ini bash script untuk install arch-Linux isinya cuman instalasi basic ajah (timezone, locale, hostname) terminal only buat install di bare metal yang UEFI sebelum install desktop environment.
isinya bikin partisi dari disk yang dibutuhin (boot, swap, /), mounting, pacstrap, ssh.
untuk ssh harus di-start dan di-enable dlu biar jalan "systemctl status sshd",
user root password awikwok123, udah ada network manager jd tinggal pake aja "nmtui".

cara pakenya itu setelah live boot ISO arch linuxnya masuk ke direktori /root (bebas sih)
trus ya tinggal:

curl -O https://raw.githubusercontent.com/mzikrialviansy12/install-arch/refs/heads/main/instal-arch.sh

abis itu chmod:
chmod +x instal-arch.sh

langsung ajah jalankan:
./instal-arch.sh
