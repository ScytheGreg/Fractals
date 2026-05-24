if [ $# -eq 0 ]
then
    echo "Poprawne użycie: testy_blednego_wejscia.sh <ścieżka do pliku binarnego testowanego programu>"
fi

BRED='\033[1;31m'
NC='\033[0m' # No Color

for filename in tests/testy_blednego_wejscia/*
do
    echo $filename
    $1 0 < $filename > /dev/null
    
    if [ $? -ne 1 ]
    then
        printf "${BRED}Program powinien zwrócić 1, a zwrócił $?.\n${NC}"
        break
    fi
done

for n in '' ' ' 'a' 'A' '-1' '4294967296' '10000000000000000000'
do
    echo "Testowanie błędnego n = $n"
    echo "" | $1 $n > /dev/null

    if [ $? -ne 1 ]
    then
        echo "Program powinien zwrócić 1, a zwrócił $?"
        break
    fi
done