#!/bin/bash

date=20240415
url=https://dumps.wikimedia.org/other/cirrussearch/${date}/enwikiquote-${date}-cirrussearch-content.json.gz
raw_file=wikiquote_raw.json.gz


# download the elasticsearch dump file from wikimedia.
if [ -e $raw_file ]; then
    echo 'wikiquote dump file already exists, skipping download'
else 
    echo "downloading wikiquote dump file"
    wget $url -O $raw_file
    # if wget did not return 200 then bail
    if [ $? -ne 0 ]; then
        echo 'failed to download dump file'
        # clean up empty file that wget wrote.
        rm $raw_file
        exit 1
    fi
fi


# split the large dump file into many smaller files.
# during the split pipe each line through our custom formatter which removes data we won't be using. 
echo 'splitting dump file into smaller chunks'
mkdir -p chunks
gunzip -c $raw_file | split -d --filter='python3 format_bulk_data.py > $FILE' -l 500 - ./chunks/wikiquote_chunk_


# create the elastic index we will load the data into
echo 'creating elasticsearch index' 
curl --fail-with-body --silent -w '\n' --insecure -u elastic:elastic \
    -XPUT "https://localhost:9200/wikiquote" \
    -H "Content-Type: application/json" \
    -d @index_settings.json
# fail if could not create index
if [ $? -ne 0 ]; then
    echo 'failed to create elasticsearch index'
    exit 1
fi


# use the bulk api to load each chunk into elastic
file_count=$(ls chunks -1q | wc -l)
i=1
for file_name in chunks/*; do
    echo "loading chunk: ${i}/${file_count}"
    curl --fail-with-body --insecure -u elastic:elastic \
        --silent --output /dev/null --show-error \
        -H "Content-Type: application/x-ndjson" \
        -XPOST 'https://localhost:9200/wikiquote/_bulk' \
        --data-binary @"${file_name}"
    i=$((i + 1))
done
# flush to ensure all elastic writes all data to index
curl --fail-with-body --silent --insecure -u elastic:elastic \
    -X POST "https://localhost:9200/wikiquote/_flush?pretty"


# remove the chunks and original dump now that they've been loaded into elastic
echo 'removing dump file and chunks'
rm -r chunks
rm $raw_file


echo 'ingest complete'