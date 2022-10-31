#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# update_git_reference updates the git references
update_git_reference() {
    local giturl="$1"
    local ref="$2"
    local file="$3"

    sed -i -e "s,github.com/openshift-pipelines/pipeline-service,$giturl,g" "$file"
    sed -i -e "s,ref=v0.8.1,ref=$ref,g" "$file"
}
