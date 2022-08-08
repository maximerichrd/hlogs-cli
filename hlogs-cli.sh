#!/usr/bin/env bash
#╦ ╦╦  ╔═╗╔═╗╔═╗    ┌─┐┬  ┬
#╠═╣║  ║ ║║ ╦╚═╗    │  │  │
#╩ ╩╩═╝╚═╝╚═╝╚═╝────└─┘┴─┘┴
                          
CURRENT_TIMEZONE=$(date +"%z")
WORK_DIR="$(dirname "$0")"
CONFIG_FILE="$WORK_DIR/.env"

# COLORS
OK_COLOR='\033[1;32m'
USER_CHOICE_COLOR='\033[1;36m'
INFO_COLOR='\033[37m'
NO_COLOR='\033[0m'
ok_color() { echo -e "${OK_COLOR}$1${NO_COLOR}"; if [ -n "$2" ]; then echo; fi }
user_color() { echo -e "${USER_CHOICE_COLOR}$1${NO_COLOR}"; if [ -n "$2" ]; then echo; fi }
info_color() { echo -e "${INFO_COLOR}$1${NO_COLOR}"; if [ -n "$2" ]; then echo; fi }
mixed_info_ok_color() { echo -e "${INFO_COLOR}$1${NO_COLOR}${OK_COLOR}$2${NO_COLOR}${INFO_COLOR}$3${NO_COLOR}${OK_COLOR}$4${NO_COLOR}"; }

echo
echo -e "${OK_COLOR}╦ ╦╦  ╔═╗╔═╗╔═╗    ┌─┐┬  ┬"
echo -e "${FAKE_COL}╠═╣║  ║ ║║ ╦╚═╗    │  │  │"
echo -e "${FAKE_COL}╩ ╩╩═╝╚═╝╚═╝╚═╝────└─┘┴─┘┴${NO_COLOR}"

# HELPERS
join_by() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}
change_date_to_utc() {
  date -u \
    -jf "%Y-%m-%dT%H:%M:%S %z" \
    "${1} ${CURRENT_TIMEZONE}" \
    "+%Y-%m-%dT%H:%M:%S.000Z";
}
check_date_format() {
  date -jf "%Y-%m-%dT%H:%M:%S%S" "${1}" > /dev/null 2>&1; 

  local res=$?
  echo $res
}
delete_line_in_terminal() {
  echo -n "$(tput cuu1)$(tput dl1)"
}
get_env_value() {
  echo -n "$1" | cut -f2 -d'='
}

##################################
# STEP 1: GET CONFIG FROM ENV FILE
##################################

while read -r line; do

  type=${line%=*}

  case "$type" in
    INDEX)
    INDEXES+=("$(get_env_value $line)") 
    ;;

    DEFAULT_INDEX)
    DEFAULT_INDEX=("$(get_env_value $line)") 
    ;;

    KIBANA_BASE_URL)
    KIBANA_BASE_URL=("$(get_env_value $line)") 
    ;;

    KIBANA_URI)
    KIBANA_URI=("$(get_env_value $line)") 
    ;;

    COMPONENT_SCAN_START_DATE)
    COMPONENT_SCAN_START_DATE=("$(get_env_value $line)") 
    ;;

    COMPONENT_SCAN_END_DATE)
    COMPONENT_SCAN_END_DATE=("$(get_env_value $line)") 
    ;;

  esac

done < <(grep \
-e '^INDEX' \
-e '^DEFAULT_INDEX' \
-e '^KIBANA_BASE_URL' \
-e '^KIBANA_URI' \
-e '^COMPONENT_SCAN_START_DATE' \
-e '^COMPONENT_SCAN_END_DATE' \
"${CONFIG_FILE}");

###########################
# STEP 2: START and WELCOME
###########################
echo


# Check Kibana connection

kibana_status_code=$(curl --write-out "%{http_code}\n" --silent --output /dev/null https://$KIBANA_BASE_URL)

if [ "$kibana_status_code" -ne 200 ] ; then
  echo
  info_color "> Failed to connect to Kibana baseURL \n> https://$KIBANA_BASE_URL"
  echo
  info_color "> You may retry with a VPN \n> or setup the Kibana baseURL in the .env file "
  echo
  user_color "> Aborting..."
  echo
  exit 1
else
  ok_color "> Welcome !"
fi

echo

############################################
# STEP 3: BUILD AND PRINT INDEX_MENU TO USER
############################################
echo

for index in ${INDEXES[@]}; do
    menu="$menu$(echo -n "$index")\n"
done

info_color "> choose an index ..."

# using fzf
index_choice="$(printf "$menu" | fzf)"
fzf_ret="$?"

# Abort if no index selected
# else print the user choice
if [ -z $index_choice ] || [ $fzf_ret -ne 0 ]; then 
  info_color "> Aborting..."
  exit 1
else
  user_color "> $index_choice" "nl"
fi

######################################
# STEP 4: PRINT COMPONENT_MENU TO USER
######################################
echo

info_color "> choose one component ..."
info_color "> or more using TAB ..."

# Now fetch a list of all distinct components from Kibana
# using fzf --multi
component_choice=$(curl -s --location --request POST https://$KIBANA_BASE_URL'/_plugin/kibana/elasticsearch/_msearch?rest_total_hits_as_int=true&ignore_throttled=true' \
--header 'authority: '$KIBANA_BASE_URL'' \
--header 'accept: application/json, text/plain, */*' \
--header 'content-type: application/x-ndjson' \
--header 'kbn-version: 7.1.1' \
--header 'origin: https://'$KIBANA_BASE_URL'' \
--header 'referer: https://'$KIBANA_BASE_URL'/_plugin/kibana/app/kibana' \
--header 'sec-fetch-dest: empty' \
--header 'sec-fetch-mode: cors' \
--header 'sec-fetch-site: same-origin' \
--data-raw '{"index":"'$DEFAULT_INDEX'*","ignore_unavailable":true,"preference":1659574718091}
{"size":0,"sort":[{"@timestamp":{"order":"desc","unmapped_type":"boolean"}}],"_source":{"includes":["component"]},"aggs":{"distinct_components":{"terms":{"field":"component.keyword","size":200}}},"query":{"range":{"@timestamp":{"gte": "'$COMPONENT_SCAN_START_DATE'","lt": "'$COMPONENT_SCAN_END_DATE'"}}},"highlight":{},"timeout":"60000ms"}
' | jq -r '.responses[].aggregations.distinct_components.buckets[].key' | sort -fd | fzf --multi )

fzf_ret="$?"

# Abort if no component selected
if [ ${#component_choice[@]} -eq 0 ] || [ $fzf_ret -ne 0 ]; then 
  info_color "> Aborting..."
  exit 1
fi

component_count=0
for comp in ${component_choice[@]}; do
    # set variables for last step (url)
    component_count=$((component_count + 1)) 
    comp_array+=(${comp})
    comp_query_array+=("(match_phrase:(component:${comp}))")

    # print user choice
    user_color "> $comp"

done

echo

######################################################
# STEP 5: ASK, BUILD and PRINT the Kibana search query
######################################################
echo

info_color "> Enter search query ..."
read search_query
delete_line_in_terminal

# add leading double-quote
query='"'
# handle AND + OR cases
# We want these two strings 
# to be the only unquoted strings in the query
for word in $search_query; do
  case $word in
    # Add ~ as an identifier
    AND) query="$query~ $(echo -n "$word") ~" ;;

    OR) query="$query~ $(echo -n "$word") ~" ;;

    *) 
      last_char=$(echo -n $query | tail -c 1)
      if [ $last_char == '~' ] || [ $last_char == '"' ]; then
        query="$query$(echo -n "$word")"
      else
        query="$query $(echo -n "$word")"
      fi ;;
  esac
done
# add trailing double-quote
query=$query'"'

# replace all ~ identifiers with "
query=$(echo -n $query | sed -e s/~/\"/g)

# if query is empty, remove our useless leading and trailing double-quotes
if [ "'${query}'" == "'\"\"'" ]; then
  query=''
  user_color "> search for: all logs" "nl"
else
  user_color "> search for: ${query}" "nl"
fi

####################################################
# STEP 6: ASK, BUILD and PRINT the Kibana time-range
####################################################
echo
echo -ne ${INFO_COLOR}
read -n 1 -p "> Need time-range ? (if not, press <enter>) " time_range_opt
echo -ne ${NO_COLOR}


default_fromdate=$(date "+%Y-%m-%dT00:00:00")
default_todate=now
default_printed_todate=$(date "+%Y-%m-%dT%H:%M:%S")

if [ "$time_range_opt" != "" ]; then

  echo
  echo
  mixed_info_ok_color "> Waiting for a " "\"FROM DATE\" " "with this format: " "$default_fromdate"
  info_color "  (or press Enter to get default: FROM TODAY)"

  echo
  echo -ne ${INFO_COLOR}
  read -p "> FROM DATE: " -e user_fromdate
  echo -ne ${NO_COLOR}
  delete_line_in_terminal
  

  if [ -n "$user_fromdate" ];then
    if [ $(check_date_format $user_fromdate) -gt 0 ]; then
     info_color "> Wrong date format, switching to default..."
     user_color "> FROM TODAY ..." "nl"
     user_fromdate=$default_fromdate
    else
     user_color "> FROM $user_fromdate ..." "nl"
    fi
  else
    user_color "> FROM TODAY ..." "nl"
  fi

  mixed_info_ok_color "> Waiting for a " "\"TO DATE\" " "with this format: " "$default_printed_todate"
  info_color "  (or press Enter to get default: TO NOW)"

  echo
  echo -ne ${INFO_COLOR}
  read -p "> TO DATE: " -e user_todate
  echo -ne ${NO_COLOR}
  delete_line_in_terminal

  if [ -n "$user_todate" ];then
    if [ $(check_date_format $user_todate) -gt 0 ]; then
     info_color "> Wrong date format, switching to default..."
     user_color "> TO NOW" "nl"
     user_todate=$default_todate
    else
     user_color "> TO $user_todate" "nl"
    fi
  else
    user_color "> TO NOW !" "nl"
  fi
else
  echo
  user_color "> FROM TODAY ..."
  user_color "> TO NOW !"
fi

#####################################
# STEP 7: BUILD AND LAUNCH KIBANA URL
#####################################
echo

## Modify our user or default dates to match with UTC
if [ -n "$user_fromdate" ];then
   from_date="$(change_date_to_utc $user_fromdate 2>/dev/null)"
else
   from_date="$(change_date_to_utc $default_fromdate 2>/dev/null)"
fi

if [ -n "$user_todate" ] && [ ${user_todate} != "now" ];then
   to_date="$(change_date_to_utc $user_todate 2>/dev/null)"
else
   to_date="${default_todate}"
fi

## prepare our components to pass inside the Kibana URL
components=$(join_by , ${comp_array[@]})
components_with_space=$(join_by ,%20 ${comp_array[@]})
components_query=$(join_by , ${comp_query_array[@]})

## Say bye before opening the Kibana URL
echo
ok_color "> Bye !" "nl"

## Open the Kibana URL inside browser

if [ ${component_count} == 1 ]; then

open "https://${KIBANA_BASE_URL}${KIBANA_URI}?\
_g=(\
filters:!(),\
refreshInterval:(pause:!t,value:3000),\
time:(from:'${from_date}',to:'${to_date}'))&\
_a=(\
columns:!(message,component,level),\
filters:!(('$state':(store:appState),\
meta:(alias:!n,disabled:!f,index:${index_choice},\
key:component,negate:!f,params:!($component_choice),\
type:phrases,\
value:$component_choice),\
query:(bool:(minimum_should_match:1,should:!((match_phrase:(component:$component_choice))))))),\
index:$index_choice,interval:auto,\
query:(language:kuery,query:'$(python -c "import urllib, sys; print urllib.quote(sys.argv[1])" "$query")'),\
sort:!('@timestamp',desc))"

else

open "https://${KIBANA_BASE_URL}${KIBANA_URI}?\
_g=(filters:!(),\
refreshInterval:(pause:!t,value:3000),\
time:(from:'${from_date}',to:${to_date}))&\
_a=(columns:!(message,component,level),\
filters:!(('$state':(store:appState),\
meta:(alias:!n,disabled:!f,index:${index_choice},\
key:component,negate:!f,params:!($components),\
type:phrases,value:'$components_with_space'),\
query:(bool:(minimum_should_match:1,should:!($components_query))))),\
index:$index_choice,interval:auto,\
query:(language:kuery,query:'$(python -c "import urllib, sys; print urllib.quote(sys.argv[1])" "$query")'),\
sort:!('@timestamp',desc))"

fi

exit 0
