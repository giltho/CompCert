virtualenv --python=python3 venv
source venv/bin/activate
pip install -r compileUtils/requirements.txt
rm -rf customlib
find . -iname '*.ml' -or -iname '*.mli' | grep -v '_esy\|_build' | depgraph > depend.dot
mkdir customlib
cp compileUtils/dune_for_compcert customlib/dune
python compileUtils/makeCopyScript.py
sh moveScript.sh