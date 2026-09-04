#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>

#define MAX_JPEG_INPUT_BYTES (64L * 1024L * 1024L)
#define MAX_SAVED_MARKER_BYTES 65500U

typedef struct {
  struct jpeg_error_mgr base;
  jmp_buf jump;
  char message[JMSG_LENGTH_MAX];
} jpeg_error;

static void fail(j_common_ptr cinfo) {
  jpeg_error *error = (jpeg_error *)cinfo->err;
  (*cinfo->err->format_message)(cinfo, error->message);
  longjmp(error->jump, 1);
}

static void usage(void) {
  fprintf(stderr, "usage: mozjpeg-helper --quality <0-100> --output <destination> --preserve-metadata <source>\n");
}

int main(int argc, char *argv[]) {
  if (argc != 7 || strcmp(argv[1], "--quality") != 0 ||
      strcmp(argv[3], "--output") != 0 ||
      strcmp(argv[5], "--preserve-metadata") != 0) {
    usage();
    return 2;
  }

  char *end = NULL;
  long quality = strtol(argv[2], &end, 10);
  if (*argv[2] == '\0' || *end != '\0' || quality < 0 || quality > 100 ||
      strcmp(argv[4], argv[6]) == 0) {
    usage();
    return 2;
  }

  FILE *input = fopen(argv[6], "rb");
  if (input == NULL) {
    perror("Cannot open JPEG source");
    return 1;
  }
  FILE *output = fopen(argv[4], "wb");
  if (output == NULL) {
    perror("Cannot open JPEG destination");
    fclose(input);
    return 1;
  }
  if (fseek(input, 0, SEEK_END) != 0 || ftell(input) < 0 ||
      ftell(input) > MAX_JPEG_INPUT_BYTES || fseek(input, 0, SEEK_SET) != 0) {
    fprintf(stderr, "MozJPEG: JPEG input exceeds the 64 MiB safety limit.\n");
    fclose(output);
    fclose(input);
    remove(argv[4]);
    return 1;
  }

  struct jpeg_decompress_struct input_info;
  struct jpeg_compress_struct output_info;
  jpeg_error input_error = {0};
  jpeg_error output_error = {0};
  volatile int input_created = 0;
  volatile int output_created = 0;

  input_info.err = jpeg_std_error(&input_error.base);
  input_error.base.error_exit = fail;
  output_info.err = jpeg_std_error(&output_error.base);
  output_error.base.error_exit = fail;

  if (setjmp(input_error.jump) || setjmp(output_error.jump)) {
    const char *message = input_error.message[0] ? input_error.message : output_error.message;
    fprintf(stderr, "MozJPEG: %s\n", message);
    if (output_created) jpeg_destroy_compress(&output_info);
    if (input_created) jpeg_destroy_decompress(&input_info);
    fclose(output);
    fclose(input);
    remove(argv[4]);
    return 1;
  }

  jpeg_create_decompress(&input_info);
  input_created = 1;
  jpeg_stdio_src(&input_info, input);
  jpeg_save_markers(&input_info, JPEG_APP0 + 1, MAX_SAVED_MARKER_BYTES);
  jpeg_save_markers(&input_info, JPEG_APP0 + 2, MAX_SAVED_MARKER_BYTES);
  jpeg_read_header(&input_info, TRUE);
  for (jpeg_saved_marker_ptr marker = input_info.marker_list; marker != NULL; marker = marker->next) {
    if (marker->original_length > MAX_SAVED_MARKER_BYTES) {
      fprintf(stderr, "MozJPEG: EXIF or ICC metadata marker exceeds the safety limit.\n");
      jpeg_destroy_decompress(&input_info);
      fclose(output);
      fclose(input);
      remove(argv[4]);
      return 1;
    }
  }
  input_info.out_color_space = input_info.jpeg_color_space == JCS_GRAYSCALE ? JCS_GRAYSCALE : JCS_RGB;
  jpeg_start_decompress(&input_info);

  jpeg_create_compress(&output_info);
  output_created = 1;
  jpeg_stdio_dest(&output_info, output);
  output_info.image_width = input_info.output_width;
  output_info.image_height = input_info.output_height;
  output_info.input_components = input_info.output_components;
  output_info.in_color_space = input_info.output_components == 1 ? JCS_GRAYSCALE : JCS_RGB;
  jpeg_set_defaults(&output_info);
  jpeg_set_quality(&output_info, (int)quality, TRUE);
  output_info.optimize_coding = TRUE;
  jpeg_start_compress(&output_info, TRUE);

  for (jpeg_saved_marker_ptr marker = input_info.marker_list; marker != NULL; marker = marker->next) {
    if (marker->marker == JPEG_APP0 + 1 || marker->marker == JPEG_APP0 + 2) {
      jpeg_write_marker(&output_info, marker->marker, marker->data, marker->data_length);
    }
  }

  JSAMPARRAY scanline = (*input_info.mem->alloc_sarray)((j_common_ptr)&input_info, JPOOL_IMAGE, input_info.output_width * input_info.output_components, 1);
  while (input_info.output_scanline < input_info.output_height) {
    jpeg_read_scanlines(&input_info, scanline, 1);
    jpeg_write_scanlines(&output_info, scanline, 1);
  }
  jpeg_finish_compress(&output_info);
  jpeg_finish_decompress(&input_info);
  jpeg_destroy_compress(&output_info);
  jpeg_destroy_decompress(&input_info);
  fclose(output);
  fclose(input);
  return 0;
}
