#!/bin/bash
echo 'Starting test hook...'
GEMINI_EXIT_CODE=0
echo 'GEMINI_EXIT_CODE set to: '$GEMINI_EXIT_CODE
if [[ $GEMINI_EXIT_CODE -eq 124 ]]; then
    echo 'Timeout detected'
elif [[ $GEMINI_EXIT_CODE -ne 0 ]]; then
    echo 'Error detected'
else
    echo 'Success detected'
fi
