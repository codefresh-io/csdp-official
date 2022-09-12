import time
import requests
import json
import csv
from tempfile import NamedTemporaryFile

import shutil
from requests.models import Response

url = "http://local.codefresh.io/2.0/api/graphql"
finished_runtimes = set()
DATA_FIELDS = [
    "name",
    "installationStatus",
    "healthStatus",
    "syncStatus",
    "createdAt",
    "finishedAt",
]


def get_current_time():
    t = time.localtime()
    return time.strftime("%H:%M:%S", t)


def doGql(query, variables) -> Response:
    headers = {
        "Authorization": "62655c9d0184127172f4e825.a59527fe778be7489c5f79d1d742f8f9"
    }
    return requests.post(
        url, json={"query": query, "variables": variables}, headers=headers
    )


def write_to_file(fields, update=False):
    file_name = 'runtimes.csv'
    temp_file = NamedTemporaryFile(mode='a+', delete=False)
    with open(file_name, "r") as csv_file, temp_file:
        writer = csv.DictWriter(temp_file, fieldnames=DATA_FIELDS)
        reader = csv.DictReader(csv_file, fieldnames=DATA_FIELDS)
        for row in reader:
            if update and row["name"] == fields["name"]:
                print('Update')
                for k, v in fields.items():
                    row[k] = v
            writer.writerow(row)
        if not update:
            writer.writerow(fields)

    shutil.move(temp_file.name, file_name)


def createManagedRuntime(name):
    print(f"Creating managed runtime {name}")

    mutation = """
        mutation CreateManagedRuntime($name: String) {
            createManagedRuntime(name: $name)
        }
    """

    variables = {"name": name}

    doGql(mutation, variables)
    write_to_file({"name": name, "createdAt": get_current_time()})


def getManagedRuntimes():
    query = """
        query Runtimes($managed: Boolean) {
            runtimes(managed: $managed) {
                edges {
                    node {
                        metadata {
                            name
                        }
                        installationStatus
                        healthStatus
                        syncStatus
                    }
                }
            }
        }
    """

    variables = {"managed": True}

    r = doGql(query, variables)
    return [runtime["node"] for runtime in r.json()["data"]["runtimes"]["edges"]]


if __name__ == "__main__":
    RUNTIME_NAME = 'codefresh-hosted'
    num_runtimes_to_create = 20
    start_at = 0
    for i in range(start_at, num_runtimes_to_create):
        runtime_name = f'{RUNTIME_NAME}-{i}'
        createManagedRuntime(runtime_name)

    while True:
        if len(finished_runtimes) == num_runtimes_to_create - start_at:
            print(f'All {num_runtimes_to_create} runtimes were created!!!')
            exit(0)
        runtimes = getManagedRuntimes()
        for runtime in runtimes:
            if runtime["metadata"]["name"] not in finished_runtimes:
                if runtime["installationStatus"] in ["COMPLETED", "FAILED"]:
                    write_to_file(
                        {
                            "name": runtime["metadata"]["name"],
                            "installationStatus": runtime["installationStatus"],
                            "healthStatus": runtime["healthStatus"],
                            "syncStatus": runtime["healthStatus"],
                            "finishedAt": get_current_time(),
                        },
                        update=True,
                    )
                    finished_runtimes.add(runtime["metadata"]["name"])
