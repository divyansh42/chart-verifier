#!/usr/bin/env sh

echo "KUBECONFIG is '$KUBECONFIG'"
if [ -z "$KUBECONFIG" ]; then
    echo "Fatal: \$KUBECONFIG nmust be set in the environment. Please set KUBECONFIG to the path to your Kubernetes config file."
    exit 1
fi

echo "Chart URI to certify is '$CHART_URI'"

if [ -z "$CHART_URI" ]; then
    echo "Fatal: \$CHART_URI must be set in the environment. Please set CHART_URI to point to the chart to certify."
    exit 1
fi

config_args=""
# if [ -n "$CONFIG_FILE_PATH" ]; then
#     echo "Config file path is '$CONFIG_FILE_PATH'"
#     config_args="--config $CONFIG_FILE_PATH"
# fi

echo "Report type is '$REPORT_TYPE'"

set -e

# Echo the usage of both commands, so users know what the inputs mean.
echo "::group::Print 'verify' usage"
chart-verifier verify --help
echo "::endgroup::"

echo "::group::Print 'report' usage"
chart-verifier report --help
echo "::endgroup::"

report_filename=chart-verifier-report.yaml
results_filename=results.json

verify_extra_args="$@"

### Run 'verify'

# https://github.com/redhat-certification/chart-verifier/issues/208

verify_cmd="chart-verifier $config_args verify --kubeconfig $KUBECONFIG $verify_extra_args $CHART_URI"
echo "Running: $verify_cmd"
$verify_cmd 2>&1 | tee $report_filename

# echo "::group::Print full report"
# cat $report_filename
# echo "::endgroup::"

### Run 'report'

report_cmd="chart-verifier $config_args report $REPORT_TYPE $report_filename"
echo "Running: $report_cmd"
$report_cmd 2>&1 | tee $results_filename

# echo "::group::Print full results"
# cat $results_filename
# echo "::endgroup::"

### Parse the report JSON to detect passes and fails

passed=$(jq -r '.results.passed' $results_filename)
failed=$(jq -r '.results.failed' $results_filename)

if [ -z "$passed" ] || [ -z "$failed" ]; then
    echo "Fatal: failed to parse JSON from $results_filename"
    exit 1
fi

green="\u001b[32m"
red="\u001b[31m"
reset="\u001b[0m"
if [ "$passed" == "0" ]; then
    echo -e "${red}${passed} checks passed${reset}"
elif [ "$passed" == "1" ]; then
    echo -e "${green}${passed} check passed${reset}"
else
    echo -e "${green}${passed} checks passed${reset}"
fi

exit_status=1
if [ "$failed" == "0" ]; then
    echo -e "${green}${failed} checks failed${reset}"
    exit_status=0
elif [ "$failed" == "1" ]; then
    # Echo with colon and no newline, so the one message looks natural
    echo -ne "${red}${failed} check failed${reset}:"
else
    # Echo with colon but with newline
    echo -e "${red}${failed} checks failed${reset}:"
fi

if [ "$exit_status" == "1" ]; then
    messages_file=messages.txt
    jq -r '.results.message[]' $results_filename > $messages_file

    while read line; do
        echo "  - $line"
    done < $messages_file

    echo

    if [ "$FAIL" != "false" ] && [ "$FAIL" != "no" ]; then
        echo "Exiting with error code due to failed checks"
    else
        echo "\$FAIL is $FAIL, not exiting with an error code"
        exit_status=0
    fi
fi

# echo "exit $exit_status"
exit $exit_status
