package protocol

import "testing"

func BenchmarkBuildFrame(b *testing.B) {
	var ip [4]byte
	data := make([]byte, 512)
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_ = BuildFrame(1, 0, ip, 53, data)
	}
}
