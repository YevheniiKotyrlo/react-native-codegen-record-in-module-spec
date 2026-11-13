#!/usr/bin/env bash
# Parses ReproducerApp/specs/NativeRules.ts with react-native's codegen, nightly unless an argument names another
# version, through combine-js-to-schema-cli.js, beside a copy whose Rule.matched is {[key: string]: unknown}, and
# prints the element type each schema gives the ReadonlyArray<Rule> parameter.
# Exits 1 while codegen parses the Record spelling with no error and an AnyTypeAnnotation element, 0 once it reads
# the element as it reads the index-signature one or refuses the spec with an error, and 2 when a step fails.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
spec="${here}/ReproducerApp/specs/NativeRules.ts"
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

step "parse each spelling of Rule.matched with ${codegen}/lib/cli/combine/combine-js-to-schema-cli.js"
grep -q 'readonly matched: Record<string, unknown>;' "${spec}" || fail "the spec's Rule.matched is not Record<string, unknown>"
read_element='const [module] = Object.values(require(require("path").resolve(process.argv[1])).modules);
console.log(JSON.stringify(module.spec.methods[0].typeAnnotation.params[0].typeAnnotation.elementType));'

# Parses the spec with Rule.matched spelled $2, and sets outcome to parsed or refused and result to the parameter's
# element type in the schema or the error codegen printed.
parse() {
  local name=$1 type=$2
  mkdir -p "${name}" || fail "create ${name}"
  sed -e "s/readonly matched: Record<string, unknown>;/readonly matched: ${type};/" "${spec}" > "${name}/NativeRules.ts" ||
    fail "write the ${name} spec"
  if node "${codegen}/lib/cli/combine/combine-js-to-schema-cli.js" "${name}/schema.json" "${name}/NativeRules.ts" \
    > "${name}/codegen.log" 2>&1; then
    outcome=parsed
    result=$(node -e "${read_element}" "${name}/schema.json") || fail "read the element type of the ${name} schema"
  else
    outcome=refused
    result=$(grep -m 1 -E '^[A-Za-z]*Error: ' "${name}/codegen.log") ||
      fail "codegen stopped on the ${name} spec with no error"
  fi
  echo "matched: ${type} -> ${outcome}: ${result}"
}

parse record 'Record<string, unknown>'
record=${result} record_outcome=${outcome}
parse index-signature '{[key: string]: unknown}'
index_signature=${result} index_signature_outcome=${outcome}

if [[ "${index_signature_outcome}" != parsed || "${index_signature}" == *AnyTypeAnnotation* ]]; then
  finish 2 "react-native ${version}'s codegen does not read the index-signature Rule as an object element"
fi
if [[ "${record_outcome}" == refused || "${record}" == "${index_signature}" ]]; then
  finish 0 "react-native ${version}'s codegen no longer turns ReadonlyArray<Rule> into an any array when Rule holds a Record"
fi
if [[ "${record}" == '{"type":"AnyTypeAnnotation"}' ]]; then
  finish 1 "react-native ${version}'s codegen turns ReadonlyArray<Rule> into an any array, with no error, when Rule holds a Record"
fi
finish 2 "react-native ${version}'s codegen gives the Record Rule another element type: ${record}"
