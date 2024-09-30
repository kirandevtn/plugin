sleep_time=5

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}
if [ $Timeout -gt 100 ]; then
    sleep_time=15
fi
echo "Starting the script"
echo "---------------------"
app_list=$(curl -s -H "token:$DevtronApiToken" "$DevtronEndpoint/orchestrator/app/autocomplete")
code=00
code=$(echo "$app_list" | jq -r ".code")
if [ "$code" -ne 200 ];then
    result=$(echo "$app_list" | jq -r '.result')
    echo "Error: $result! Please check the API token provided"
    exit 1
fi
if is_number $DevtronApp;then
    app_id=$DevtronApp
else
    app_id=$(echo "$app_list" | jq -r --arg DevtronApp "$DevtronApp" '.result[] | select(.name == $DevtronApp) | .id')
fi
if ! [ "$app_id" ];then
    echo "App $DevtronApp not found! Please check the details entered. for eg.(DevtronApp,DevtronEnv,DevtronEndpoint)"
    exit 1
fi
app_workflow=$(curl -s -H "token:$DevtronApiToken" "$DevtronEndpoint/orchestrator/app/app-wf/view/$app_id")
if is_number "$CiPipeline";then
    ci_pipeline_id=$CiPipeline
else
    if [ "$DevtronEnv" ];then
        if is_number "$DevtronEnv";then
            ci_pipeline_id=$(echo "$app_workflow" | jq -r --argjson DevtronEnv "$DevtronEnv" '.result.cdConfig.pipelines[] | select(.environmentId == $DevtronEnv) | .ciPipelineId')
        else
            ci_pipeline_id=$(echo "$app_workflow" | jq -r --arg DevtronEnv "$DevtronEnv" '.result.cdConfig.pipelines[] | select(.environmentName == $DevtronEnv) | .ciPipelineId')
        fi
    elif [ "$CiPipeline" ];then
        ci_pipeline_id=$(echo "$app_workflow" | jq -r --arg CiPipeline "$CiPipeline" '.result.ciConfig.ciPipelines[] | select(.name == $CiPipeline) | .id')
    else
        echo "You must provide one of the fields: DevtronEnv or CiPipeline"
        echo "Error: DevtronEnv or ciPipelineId not provided"
        exit 1
    fi
fi
if [ ! "$ci_pipeline_id" ];then
    echo "Please check the CI Pipeline Name or DevtronEnv"
    exit 1
fi

build_art=""
json_response=$(curl -s "$DevtronEndpoint/orchestrator/app/ci-pipeline/$ci_pipeline_id/material" \
         -H "token: $DevtronApiToken")
id_array=()
id_array=($(echo "$json_response" | jq -r '.result[].id'))

if [ "$GitCommitHash" ];then
    commits=()
    IFS=','
    for value in $GitCommitHash; do
        commits+=("$value")
    done
    IFS=' '
    mat_payload=()
    comm_len=${#commits[@]}
    id_len=${#id_array[@]}
    if [ "$comm_len" -ne "$id_len" ];then
        echo "Please check the GitCommitHash"
        exit 1
    fi
    for commit in "${commits[@]}"; do
        for id in "${id_array[@]}"; do
            check_commit=$(curl -s "$DevtronEndpoint/orchestrator/app/commit-info/$id/$commit" \
                -H "token: $DevtronApiToken")
            ch_code=$(echo "$check_commit" | jq -r ".code")
            if [ "$ch_code" -eq 200 ];then
                res=$(echo "$check_commit" | jq ".result")
                if [ "$res" != null ];then
                    mat_payload+=("{\"Id\":$id,\"GitCommit\":{\"Commit\":\"$commit\"}}")
                fi
            fi
        done
    done
    mat_len=${#mat_payload[@]}
    if [ "$mat_len" -ne "$id_len" ];then
        echo "Please check the commits provided"
        exit 1
    fi
    mat_payload_json=""

    # Loop through the mat_payload array and build the JSON string
    for i in "${!mat_payload[@]}"; do
        mat_payload_json+="${mat_payload[$i]}"
        # Add a comma after each element
        mat_payload_json+=","
    done

    # Remove the trailing comma from the last element
    mat_payload_json=${mat_payload_json%,}

    # Construct the full payload
    payload="{\"pipelineId\":$ci_pipeline_id,\"ciPipelineMaterials\":[$mat_payload_json],\"invalidateCache\":$IgnoreCache,\"pipelineType\":\"CI_BUILD\"}"

    # Print the payload
    echo "$payload"

    curl_req=$(curl -s "$DevtronEndpoint/orchestrator/app/ci-pipeline/trigger" \
        -H "token: $DevtronApiToken" \
        --data-raw "$payload")
    code=$(echo "$curl_req" | jq -r '.code')
    if [ "$code" -ne 200 ];then
        error=$(echo "$curl_req" | jq -r '.errors[]')
        echo "$error"
        echo "CI Pipeline details could not be found. Please check!"
        exit 1
    fi
    build_art=$(echo "$curl_req" | jq -r ".result.apiResponse")
    echo "The build with CI pipeline ID $ci_pipeline_id of application $DevtronApp is triggered using the given commits"
    echo "Gitcommithash exists"
else
    echo "No git commits provided. Taking the latest for all."

    create_payload() {
        local json=$1

        # Extracting CI pipeline materials from the JSON
        ci_pipeline_materials=$(echo "$json" | jq -c '.result[] | {Id: .id, GitCommit: {Commit: .history[0].Commit}}')

        # Constructing the payload array dynamically
        materials_payload=$(echo "$ci_pipeline_materials" | jq -s .)

        # Constructing the final payload
        payload=$(jq -n --argjson IgnoreCache $IgnoreCache --argjson materials "$materials_payload" --arg pipelineId "$ci_pipeline_id" \
        '{"pipelineId":$pipelineId|tonumber, "ciPipelineMaterials": $materials, "invalidateCache": $IgnoreCache, "pipelineType":"CI_BUILD"}')

        echo "$payload"
    }

    payload=$(create_payload "$json_response")
    echo "$payload"

    curl_req=$(curl -s "$DevtronEndpoint/orchestrator/app/ci-pipeline/trigger" \
        -H "token: $DevtronApiToken" \
        --data-raw "$payload")
    code=$(echo "$curl_req" | jq -r '.code')
    if [ "$code" -ne 200 ];then
        error=$(echo "$curl_req" | jq -r '.errors[]')
        echo "$error"
        echo "CI Pipeline details could not be found. Please check!"
        exit 1
    fi
    build_art=$(echo "$curl_req" | jq -r ".result.apiResponse")
    echo "The build with CI pipeline ID $ci_pipeline_id of application $DevtronApp is triggered using the latest commits"
fi

if [ "$Timeout" -eq -1 ] || [ "$Timeout" -eq 0 ];then
    echo "Pipeline has been Triggered"
else
    sleep 1
    fetch_status() {
        curl --silent "$DevtronEndpoint/orchestrator/app/$app_id/ci-pipeline/$ci_pipeline_id/workflow/$build_art" \
            -H "token: $DevtronApiToken"
    }
    num=$(fetch_status)
    ci_status=$(echo "$num" | jq -r ".result.status")
    echo "The current status of the build is: $ci_status";
    echo "Maximum waiting time is : $Timeout seconds"
    echo "Waiting for the process to complete......"
    start_time=$(date +%s)
    job_completed=false
    while [ "$ci_status" != "Succeeded" ]; do
        echo "The current status of the build is: $ci_status";
        if [ "$ci_status" == "Failed" ]; then
            echo "The build has been Failed"
            echo "Exiting the current process"
            exit 2
        elif [ "$ci_status" == "CANCELLED" ];then
            echo "Build has been Cancelled"
            echo "Exiting the current process"
            exit 2
        elif [ "$ci_status" == "Error" ];then
            echo "Build has encountered an Error"
            echo "Exiting the current process"
            exit 2
        fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ "$elapsed_time" -ge "$Timeout" ]; then
            echo "Timeout reached. Terminating the current process...."
            exit 2
        fi
        num=$(fetch_status)
        ci_status=$(echo "$num" | jq -r ".result.status")
        sleep $sleep_time
    done
    if [ "$ci_status" = "Succeeded" ]; then
        echo "The final status of the build is: $ci_status"
        job_completed=true
    elif [ "$ci_status" = "Failed" ]; then
        echo "The final status of the Build is: $ci_status"
    else
        echo "The final status of the Build is: $ci_status (Timeout)"
    fi

    if [ "$job_completed" = true ]; then
        echo "The triggered Build is Scuccessfully completed"
    else
        exit 2
    fi
fi
