#! /bin/bash
# we drop the first two lines, as these are the todo in the stdDef
find | grep "\.hs$" | grep -v "dist" | xargs grep "TODO" | tail -n +3