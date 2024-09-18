printf "source .bashrc\n" >> ~/.profile
printf "alias dir=\047ls -aFhl --color\047\n" > ~/.bashrc
printf "alias edit=\042/bin/nano -w\042\n" >> ~/.bashrc
printf "\n" >> ~/.bashrc
printf "export EDITOR=\042/bin/nano\042\n" >> ~/.bashrc
printf "PS1=\042\134[\134033[1;32m\134][\134\044(date \047+\045Y-\045m-\045d_\045H:\045M:\045S\047)]\134[\134033[1;35m\134][\134u\100\134h:\134w]\044\134[\134033[0m\134] \042\n" >> ~/.bashrc
printf "\n" >> ~/.bashrc
printf "function fingerprintssh() { ssh-keygen -lf \0441 -E sha256; }\n" >> ~/.bashrc
printf "function fingerprintssl() { openssl pkey -pubin -in \0441 -outform DER | openssl dgst -sha256 -c; }\n" >> ~/.bashrc
