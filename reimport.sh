#!/bin/bash
# xml2dsl で各 XML を対応するディレクトリに再インポートするスクリプト
# 実行前に: chmod +x reimport.sh
# 実行: ./reimport.sh

set -e
cd "$(dirname "$0")"

declare -A TARGETS=(
  #["CHUSO2000_Cab_Controller_IV.xml"]="CHUSO2000_Cab_Controller_V"
  ["CHUSO2000_Cab_Display_IV.xml"]="CHUSO2000_Cab_Display_IV"
  ["CHUSO2000_Driver_Assistance_IV.xml"]="CHUSO2000_Driver_Assistance_IV"
  ["CHUSO_2000_Traction_Controller.xml"]="CHUSO2000_Traction_Controller"
  ["CHUSO_2000_Door_Min.xml"]="CHUSO2000_Door_Min"
  ["CHUSO_2000_Onecar_Control.xml"]="CHUSO2000_Onecar_Control"
)

for xml in "${!TARGETS[@]}"; do
  dir="${TARGETS[$xml]}"
  echo "=== $xml -> $dir/ ==="
  mkdir -p "$dir"
  pnpm exec storm-mcl xml2dsl "$xml" --out-dir "$dir"
done

echo ""
echo "Done."
