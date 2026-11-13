/* Reference for jpeg_compare. libjpeg with nearest-neighbor chroma,
   matching the proxy decoder's documented upsampling policy. */
#include <stdio.h>
#include <stdlib.h>
#include <jpeglib.h>

int main(int argc, char **argv)
{
    if (argc != 2) return 1;
    FILE *input = fopen(argv[1], "rb");
    if (!input) return 1;
    struct jpeg_decompress_struct decoder;
    struct jpeg_error_mgr errors;
    decoder.err = jpeg_std_error(&errors);
    jpeg_create_decompress(&decoder);
    jpeg_stdio_src(&decoder, input);
    jpeg_read_header(&decoder, TRUE);
    decoder.do_fancy_upsampling = FALSE;
    decoder.dct_method = JDCT_ISLOW;
    decoder.out_color_space = JCS_RGB;
    jpeg_start_decompress(&decoder);
    JSAMPARRAY row = (*decoder.mem->alloc_sarray)
        ((j_common_ptr)&decoder, JPOOL_IMAGE, decoder.output_width * 3, 1);
    while (decoder.output_scanline < decoder.output_height) {
        jpeg_read_scanlines(&decoder, row, 1);
        for (unsigned int x = 0; x < decoder.output_width; ++x) {
            unsigned char rgba[] = {row[0][x*3], row[0][x*3+1], row[0][x*3+2], 255};
            if (fwrite(rgba, 1, 4, stdout) != 4) return 1;
        }
    }
    jpeg_finish_decompress(&decoder);
    jpeg_destroy_decompress(&decoder);
    fclose(input);
    return 0;
}
