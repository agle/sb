#!/usr/bin/env bash

set -xe

wget https://github.com/megastep/makeself/releases/download/release-2.7.1/makeself-2.7.1.run 
bash makeself-2.7.1.run

mkdir -p binout/lib

LIB=$(ldd _build/default/bin/main.exe | grep libonig | cut -f3 -d' ')
cp $LIB binout/lib
opam exec -- dune build --profile=release
cp _build/default/bin/main.exe binout/

echo '#!/usr/bin/env bash' > binout/start.sh
echo 'FN="$(realpath main.exe)"'  >> binout/start.sh
echo "export LD_LIBRARY_PATH=$(realpath lib)" >> binout/start.sh
echo 'cd "$USER_PWD" && "$FN" $@' >> binout/start.sh
chmod +x binout/start.sh

bash makeself-2.7.1/makeself.sh binout sb "site generator" ./start.sh
