#include <compression.h>
#include <stdio.h>
int main(void) {
    printf("encode scratch LZFSE: %zu bytes\n", compression_encode_scratch_buffer_size(COMPRESSION_LZFSE));
    printf("decode scratch LZFSE: %zu bytes\n", compression_decode_scratch_buffer_size(COMPRESSION_LZFSE));
    printf("encode scratch LZ4:   %zu bytes\n", compression_encode_scratch_buffer_size(COMPRESSION_LZ4));
    return 0;
}
