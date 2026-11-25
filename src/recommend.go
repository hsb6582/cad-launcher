package main

// 추천 기능 표시 (엄지척 아이콘)
//   catalog.json 기능에 "recommend": true 가 있으면 목록에서 이름 앞에 엄지척 아이콘을 붙인다.
//   트리의 '상태 그림(state image)' 자리를 쓰므로, 추천이 아닌 기능은 들여쓰기가 바뀌지 않는다.
//   아이콘은 exe 안에 넣어 두고(assets/thumb_*.png), 화면 배율에 가까운 크기를 골라 쓴다.

import (
	"bytes"
	"embed"
	"image"
	"image/draw"
	_ "image/png"
	"unsafe"
)

//go:embed assets/thumb_16.png assets/thumb_20.png assets/thumb_24.png assets/thumb_28.png assets/thumb_32.png
var thumbFS embed.FS

var (
	pImageListCreate      = comctl32.NewProc("ImageList_Create")
	pImageListReplaceIcon = comctl32.NewProc("ImageList_ReplaceIcon")
	pCreateIconIndirect   = user32.NewProc("CreateIconIndirect")
	pDestroyIcon          = user32.NewProc("DestroyIcon")
	pCreateBitmap         = gdi32.NewProc("CreateBitmap")
)

const (
	TVM_SETIMAGELIST    = 0x1109
	TVSIL_STATE         = 2
	TVIS_STATEIMAGEMASK = 0xF000
	stateRecommend      = 1 << 12 // INDEXTOSTATEIMAGEMASK(1)
)

type iconInfo struct {
	fIcon              int32
	xHotspot, yHotspot uint32
	hbmMask, hbmColor  uintptr
}

// PNG(투명 배경)를 알파 채널이 있는 아이콘으로 만든다
func pngIcon(data []byte) (uintptr, int) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return 0, 0
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	nrgba := image.NewNRGBA(image.Rect(0, 0, w, h))
	draw.Draw(nrgba, nrgba.Rect, img, b.Min, draw.Src)
	bi := bitmapInfoHeader{biWidth: int32(w), biHeight: -int32(h), biPlanes: 1, biBitCount: 32}
	bi.biSize = uint32(unsafe.Sizeof(bi))
	var bits uintptr
	color := c(pCreateDIBSection, 0, uintptr(P(&bi)), 0, uintptr(P(&bits)), 0, 0)
	if color == 0 || bits == 0 {
		return 0, 0
	}
	dst := unsafe.Slice((*byte)(unsafe.Pointer(bits)), w*h*4)
	for i := 0; i < w*h; i++ { // BGRA (알파는 곱하지 않은 값 - 아이콘 형식)
		dst[i*4], dst[i*4+1], dst[i*4+2], dst[i*4+3] = nrgba.Pix[i*4+2], nrgba.Pix[i*4+1], nrgba.Pix[i*4], nrgba.Pix[i*4+3]
	}
	mask := c(pCreateBitmap, uintptr(w), uintptr(h), 1, 1, 0)
	ii := iconInfo{fIcon: 1, hbmMask: mask, hbmColor: color}
	hi := c(pCreateIconIndirect, uintptr(P(&ii)))
	c(pDeleteObject, mask)
	c(pDeleteObject, color)
	return hi, w
}

// 목록(트리)에 추천 아이콘 목록을 붙인다 (createControls 에서 한 번)
func setupRecommendIcon() {
	want := int(16*scale + 0.5)
	best := 16
	for _, sz := range []int{16, 20, 24, 28, 32} {
		if abs(sz-want) < abs(best-want) {
			best = sz
		}
	}
	data, err := thumbFS.ReadFile("assets/thumb_" + itoa(best) + ".png")
	if err != nil {
		return
	}
	hi, w := pngIcon(data)
	if hi == 0 {
		return
	}
	il := c(pImageListCreate, uintptr(w), uintptr(w), 0x20 /*ILC_COLOR32*/, 2, 0)
	c(pImageListReplaceIcon, il, ^uintptr(0), hi) // 0번: 쓰지 않는 자리 (상태 그림 0 = 그림 없음)
	c(pImageListReplaceIcon, il, ^uintptr(0), hi) // 1번: 추천
	c(pDestroyIcon, hi)
	c(pSendMessageW, hList, TVM_SETIMAGELIST, TVSIL_STATE, il)
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
