#! /bin/sh

# Identify the platform ID and initialize the PRODUCT_ID accordingly where:
# 0x3 – bluefield2 product id
# 0x4 – bluefield3 product id
BF1_PLATFORM_ID=0x00000211
BF2_PLATFORM_ID=0x00000214
BF3_PLATFORM_ID=0x0000021c

bfversion=$(bfhcafw mcra 0xf0014.0:16)

if [ "$bfversion" = $BF2_PLATFORM_ID ]; then
   ln -sf /etc/ipmi/mlx-bf2.emu /etc/ipmi/mlx-bf.emu
elif  [ "$bfversion" = $BF3_PLATFORM_ID ]; then
   ln -sf /etc/ipmi/mlx-bf3.emu /etc/ipmi/mlx-bf.emu
elif  [ "$bfversion" = $BF1_PLATFORM_ID ]; then
   ln -sf /etc/ipmi/mlx-bf1.emu /etc/ipmi/mlx-bf.emu
fi
