#!/usr/bin/env bash
# Parses ReproducerApp/specs/NativeSample.ts with react-native's codegen, nightly unless an argument names another
# version, through combine-js-to-schema-cli.js as an app's codegen step runs it, beside copies of the spec whose
# parameter is spelled Readonly<Record<string, unknown>>, {[key: string]: unknown} and CodegenTypes.UnsafeObject.
# Exits 1 while codegen does not read Record<string, unknown> as it reads {[key: string]: unknown}, 0 once it does,
# and 2 when a step fails or codegen refuses a spelling it already reads.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
spec="${here}/ReproducerApp/specs/NativeSample.ts"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
step() { echo "== $*"; }
finish() { echo "SUMMARY: $2"; exit "$1"; }
fail() { echo "step failed: $*"; finish 2 "the reproduction stopped: $*"; }

step "toolchain"
node --version || fail "node"
npm --version || fail "npm"

release=${1:-nightly}
step "install react-native@${release}"
cd "${work}" || fail "cd"
npm init -y > /dev/null || fail "npm init"
npm install --silent --no-audit --no-fund "react-native@${release}" > install.log 2>&1 || {
  tail -n 20 install.log
  fail "npm install"
}
version=$(node -p "require('react-native/package.json').version") || fail "read react-native's version"
codegen=node_modules/@react-native/codegen
codegen_version=$(node -p "require('./${codegen}/package.json').version") || fail "read @react-native/codegen's version"
echo "react-native ${version} with @react-native/codegen ${codegen_version}"

step "environment"
npx --yes @react-native-community/cli info || echo "@react-native-community/cli info did not run"

step "parse each spelling of the parameter with ${codegen}/lib/cli/combine/combine-js-to-schema-cli.js"
grep -q 'options: Record<string, unknown>' "${spec}" || fail "the spec's parameter is not Record<string, unknown>"
read_parameter='const [module] = Object.values(require(require("path").resolve(process.argv[1])).modules);
console.log(JSON.stringify(module.spec.methods[0].typeAnnotation.params[0].typeAnnotation));'

# Parses the spec with its parameter spelled $2 and its type import naming $3, and sets outcome to parsed or refused
# and result to the parameter's annotation in the schema or the error codegen printed.
parse() {
  local name=$1 type=$2 imports=$3
  mkdir -p "${name}" || fail "create ${name}"
  sed -e "s/options: Record<string, unknown>/options: ${type}/" \
    -e "s/import type {TurboModule}/import type {${imports}}/" "${spec}" > "${name}/NativeSample.ts" ||
    fail "write the ${name} spec"
  if node "${codegen}/lib/cli/combine/combine-js-to-schema-cli.js" "${name}/schema.json" "${name}/NativeSample.ts" \
    > "${name}/codegen.log" 2>&1; then
    outcome=parsed
    result=$(node -e "${read_parameter}" "${name}/schema.json") || fail "read the parameter of the ${name} schema"
  else
    outcome=refused
    result=$(grep -m 1 -E '^[A-Za-z]*Error: ' "${name}/codegen.log") ||
      fail "codegen stopped on the ${name} spec with no error"
  fi
  echo "${type} -> ${result}"
}

parse record 'Record<string, unknown>' 'TurboModule'
record=${result} record_outcome=${outcome}
parse readonly-record 'Readonly<Record<string, unknown>>' 'TurboModule'
readonly_record=${result} readonly_record_outcome=${outcome}
parse index-signature '{[key: string]: unknown}' 'TurboModule'
index_signature=${result} index_signature_outcome=${outcome}
parse unsafe-object 'CodegenTypes.UnsafeObject' 'CodegenTypes, TurboModule'
unsafe_object_outcome=${outcome}

if [[ "${index_signature_outcome}" != parsed || "${unsafe_object_outcome}" != parsed ]]; then
  finish 2 "react-native ${version}'s codegen refuses {[key: string]: unknown} or CodegenTypes.UnsafeObject"
fi
if [[ "${record}" == "${index_signature}" && "${readonly_record}" == "${index_signature}" ]]; then
  finish 0 "react-native ${version}'s codegen reads Record<string, unknown> as it reads {[key: string]: unknown}"
fi
for refused in "${record_outcome}:${record}" "${readonly_record_outcome}:${readonly_record}"; do
  case ${refused} in
    refused:*"Unrecognized generic type 'Record' in NativeModule spec."*) ;;
    refused:*) finish 2 "react-native ${version}'s codegen refuses Record for another reason: ${refused#refused:}" ;;
    *) ;;
  esac
done
finish 1 "react-native ${version}'s codegen does not read Record<string, unknown> as it reads {[key: string]: unknown}"
