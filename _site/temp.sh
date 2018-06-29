#!/bin/bash
##############################################################################
# Description: This script invokes the AWS Price List API to get raw pricing
# for a particular AWS Service (e.g., EC2, RDS, S3, etc.) and dumps the raw JSON
# data to a file for further transformation and processing.
##############################################################################

BASE_PRICE_LIST_URI="https://pricing.us-east-1.amazonaws.com"
PRICE_LIST_API_URI="$BASE_PRICE_LIST_URI/offers/v1.0/aws/index.json"
META_DATA_DIR="../meta-data"
DATA_DIR="../data"
RAW_DATA_DIR="$DATA_DIR/raw"

# Get parameters from the CLI.
getParamsFromCli()
{
  USAGE="usage: ${0##*/} -s <Service Name>"
  
  if [ $# -eq 0 ] ; then
    echo -e "\033[33;31m No arguments supplied - ${USAGE}"
    ./send-error-notification.sh -m "No arguments supplied - ${USAGE}" -s "Failed to execute $0"
    exit 1
  fi

  while getopts ":s:" opt "$@"; do
    case $opt in
      s)
        SERVICE_FROM_CLI=$OPTARG
        ;;
      \?)
        echo -e "\033[33;31m Invalid option: -$OPTARG $USAGE  \033[0m" >&2
        ./send-error-notification.sh -m "Invalid option: -$OPTARG $USAGE" -s "Failed to execute $0"
        exit 1
        ;;
      :)
        echo -e "\033[33;31m Option -$OPTARG requires an argument. $USAGE \033[0m" >&2
        ./send-error-notification.sh -m "Service missing - [$USAGE]" -s "Failed to execute $0"
        exit 1
        ;;
      *)
        echo -e "\033[33;31m Unimplemented option: -$OPTARG - $USAGE \033[0m" >&2
        ./send-error-notification.sh -m "Unimplemented option: -$OPTARG - $USAGE" -s "Failed to execute $0"
        exit 1
        ;;
    esac
  done
}

getParamsFromCli "$@"
if [[ -z $SERVICE_FROM_CLI ]] ; then
  echo -e "\033[33;31m Service missing - [$USAGE] \033[0m"
  ./send-error-notification.sh -m "Service missing - [$USAGE]" -s "Failed to execute $0"
  exit 1
fi

# Create the Raw Data directory if it doesn't already exist.
if [ ! -d "$RAW_DATA_DIR" ] ; then
  mkdir -p $RAW_DATA_DIR
fi

# Confirm that the the Service Alias (e.g., "S3") exists in the meta-data using a case-insensitive search.
SERVICE_ALIAS=$(jq -e --arg serviceFromCli "$SERVICE_FROM_CLI" '.[] | .serviceAlias | match([$serviceFromCli, "i"]) | .string' ${META_DATA_DIR}/aws-services.json)
STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo -e "\033[33;32m Successfully got SERVICE_ALIAS from aws-services.json \033[0m"  
  else
    echo -e "\033[33;31m Failed to retrive SERVICE_ALIAS from aws-services.json \033[0m"
    ./send-error-notification.sh -m "Failed to retrive SERVICE_ALIAS from aws-services.json for $SERVICE_FROM_CLI" -s "Failed to execute $0"
    exit 1
fi

SERVICE_ALIAS=${SERVICE_ALIAS//\"} # Remove surrounding quotes from the string
echo -e "\033[33;32m Service Alias = $SERVICE_ALIAS"
if [[ -z $SERVICE_ALIAS ]] ; then
  echo -e "\033[33;31m Service Alias for [$SERVICE_FROM_CLI] Not found"
  ./send-error-notification.sh -m "Service Alias for [$SERVICE_FROM_CLI] Not found" -s "Failed to execute $0"
  exit 1
fi


# Get the real Service Code (e.g., "AmazonS3") based on the Service Alias (e.g., "S3").
SERVICE_CODE=$(jq -e --arg serviceAlias "$SERVICE_ALIAS" '.[] | select(.serviceAlias == $serviceAlias) | .serviceCode' ${META_DATA_DIR}/aws-services.json)
STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo -e "\033[33;32m Successfully got SERVICE_CODE from aws-services.json \033[0m"  
  else
    echo -e "\033[33;31m Failed to retrive SERVICE_CODE from aws-services.json \033[0m"
    ./send-error-notification.sh -m "Failed to retrive SERVICE_CODE from aws-services.json for $SERVICE_FROM_CLI" -s "Failed to execute $0"
    exit 1
fi
SERVICE_CODE=${SERVICE_CODE//\"} # Remove surrounding quotes from the string
echo -e "\033[33;32m Service Code = $SERVICE_CODE"
if [[ -z $SERVICE_CODE ]] ; then
  echo -e "\033[33;31m Service Code for Service Alias [$SERVICE_ALIAS] Not found"
  ./send-error-notification.sh -m "Service Code for Service Alias [$SERVICE_ALIAS] Not found" -s "Failed to execute $0"
  exit 1
fi


# Call the Price List API to get the pricing URI for each AWS Service.
echo "   "
echo -e "\033[33;34m Calling Price List API at [$PRICE_LIST_API_URI] to get the pricing URI for all AWS Services ... \033[0m"
echo "   "

# Use curl to make the 1st (Offer List) API call to get URIs for all Services.
# Save the JSON output to a file, and then use jq to get the URI for the Service's pricing.
PRICE_LIST_FILE_NAME="${RAW_DATA_DIR}/offer-index.json"
rm -f $PRICE_LIST_FILE_NAME
curl $PRICE_LIST_API_URI > $PRICE_LIST_FILE_NAME

STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo -e "\033[33;32m Successfully retrived offer-index.json \033[0m"  
  else
    echo -e "\033[33;31m Failed to get offer-index.json \033[0m"
    ./send-error-notification.sh -m "Failed to get offer-index.json" -s "Failed to execute $0"
    exit $STATUS
fi
chmod +x $PRICE_LIST_FILE_NAME


if ! [  -s "$PRICE_LIST_FILE_NAME" ] ; then
  echo -e "\033[33;31m $PRICE_LIST_FILE_NAME is empty. \033[0m"
  ./send-error-notification.sh -m "$PRICE_LIST_FILE_NAME is empty" -s "offer-index.json file status"
  exit 1
fi


SERVICE_PRICE_LIST_URI=$(jq -e --arg serviceCode "$SERVICE_CODE" '.offers[] | select(.offerCode == $serviceCode) | .currentVersionUrl' "$PRICE_LIST_FILE_NAME")
echo "SERVICE_PRICE_LIST_URI=$SERVICE_PRICE_LIST_URI"

if [[ -z $SERVICE_PRICE_LIST_URI ]] ; then
  echo -e "\033[33;31m The serviceCode for $SERVICE_ALIAS in aws-services.json does not match any offerCode in offer-index.json. \033[0m"
  ./send-error-notification.sh -m "The serviceCode for $SERVICE_ALIAS in aws-services.json does not match any offerCode in offer-index.json." -s "serviceCode for $SERVICE_ALIAS not found in offer-index.json"
  exit 1
fi


STATUS=$?
if [  $STATUS -eq 0 ]; then
    echo -e "\033[33;32m Successfully retrived index.json \033[0m" 
  else
    echo -e "\033[33;31m Failed to get index.json \033[0m"
    ./send-error-notification.sh -m "Failed to get index.json" -s "Failed to execute $0"
    exit $STATUS
fi

SERVICE_PRICE_LIST_URI=${SERVICE_PRICE_LIST_URI//\"} # Remove surrounding quotes from the string
SERVICE_PRICE_LIST_URI="${BASE_PRICE_LIST_URI}${SERVICE_PRICE_LIST_URI}" # Prepend the Base URI to get the full URI.


# Call the Price List API to get the pricing data for the AWS Service.
echo "   "
echo -e "\033[33;34m Calling Price List API at [$SERVICE_PRICE_LIST_URI] to get the pricing data for AWS Service - $SERVICE_CODE ... \033[0m"
echo "   "

# Convert the Service Name (e.g., "S3") to upper case so we can work with filenames.
SERVICE_PRICING_FILE_NAME="${RAW_DATA_DIR}/aws-${SERVICE_ALIAS}-pricing.json"

rm -f "$SERVICE_PRICING_FILE_NAME"

# Use curl to make the 2nd (Service pricing) API call and send output to a file for further processing.
curl "$SERVICE_PRICE_LIST_URI" > "$SERVICE_PRICING_FILE_NAME"
STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo -e "\033[33;32m Successfully retrived pricing api:-aws-${SERVICE_FOR_FILE_NAME}-pricing.json \033[0m" 
  else
    echo -e "\033[33;31m Failed to download pricing api:-aws-${SERVICE_FOR_FILE_NAME}-pricing.json \033[0m"
    ./send-error-notification.sh -m "Failed to download pricing api:-aws-${SERVICE_FOR_FILE_NAME}-pricing.json" -s "Failed to execute $0"
    exit $STATUS
fi

chmod +x "$SERVICE_PRICING_FILE_NAME"

if ! [ -s "$SERVICE_PRICING_FILE_NAME" ]; then
  echo -e "\033[33;31m $SERVICE_PRICING_FILE_NAME is empty. \033[0m"
  ./send-error-notification.sh -m "$SERVICE_PRICING_FILE_NAME is empty" -s "$SERVICE_PRICING_FILE_NAME file status"
  exit 1
fi
echo "   "
echo -e "\033[33;35m $SERVICE_CODE Pricing File Name = [$SERVICE_PRICING_FILE_NAME] \033[0m"
echo "   "

exit 0