if [ $# -eq 0 ]
then
    echo "Usage: invalid_input_tests.sh <path to program binary>"
fi

BRED='\033[1;31m'
NC='\033[0m' # No Color

for filename in tests/invalid_input_tests/*
do
    echo $filename
    $1 0 < $filename > /dev/null
    
    if [ $? -ne 1 ]
    then
        printf "${BRED}Expected exit status 1, got $?.\n${NC}"
        break
    fi
done

for n in '' ' ' 'a' 'A' '-1' '4294967296' '10000000000000000000'
do
    echo "Testing invalid n = $n"
    echo "" | $1 $n > /dev/null

    if [ $? -ne 1 ]
    then
        echo "Expected exit status 1, got $?"
        break
    fi
done
