/*
 * xcursor_extractor.c
 * 
 * A simple C program that uses libXcursor to extract cursor frames
 * and save them as PNG files for use with other applications.
 * 
 * Usage: ./xcursor_extractor <input_cursor_file> <output_directory>
 * 
 * Requires: libXcursor-dev, libpng-dev
 * Compile: gcc -o xcursor_extractor xcursor_extractor.c -lXcursor -lpng
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>

#include <X11/Xcursor/Xcursor.h>
#include <png.h>

/* Function prototypes */
int extract_cursor_frames(const char *input_file, const char *output_dir);
int save_frame_as_png(XcursorImage *image, const char *filename, int frame_num);
int create_directory(const char *path);
void separate_alpha_pixel(XcursorPixel *pixel);
void print_usage(const char *program_name);

int main(int argc, char *argv[])
{
    if (argc != 3) {
        print_usage(argv[0]);
        return 1;
    }
    
    const char *input_file = argv[1];
    const char *output_dir = argv[2];
    
    /* Check if input file exists */
    if (access(input_file, R_OK) != 0) {
        fprintf(stderr, "Error: Cannot read input file '%s': %s\n", 
                input_file, strerror(errno));
        return 1;
    }
    
    /* Create output directory */
    if (create_directory(output_dir) != 0) {
        fprintf(stderr, "Error: Cannot create output directory '%s'\n", output_dir);
        return 1;
    }
    
    /* Extract cursor frames */
    int result = extract_cursor_frames(input_file, output_dir);
    
    if (result == 0) {
        printf("Successfully extracted cursor frames to '%s'\n", output_dir);
    }
    
    return result;
}

int extract_cursor_frames(const char *input_file, const char *output_dir)
{
    FILE *fp;
    XcursorImages *images;
    XcursorComments *comments;
    int i;
    char output_path[1024];
    char info_file[1024];
    FILE *info_fp;
    
    /* Open cursor file */
    fp = fopen(input_file, "rb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot open '%s': %s\n", input_file, strerror(errno));
        return 1;
    }
    
    /* Load cursor data using libXcursor */
    if (!XcursorFileLoad(fp, &comments, &images)) {
        fprintf(stderr, "Error: '%s' is not a valid XCursor file\n", input_file);
        fclose(fp);
        return 1;
    }
    
    fclose(fp);
    
    if (!images || images->nimage == 0) {
        fprintf(stderr, "Error: No images found in cursor file\n");
        if (images) XcursorImagesDestroy(images);
        if (comments) XcursorCommentsDestroy(comments);
        return 1;
    }
    
    printf("Found %d frame(s) in cursor file\n", images->nimage);
    
    /* Create info file with cursor metadata */
    snprintf(info_file, sizeof(info_file), "%s/cursor_info.txt", output_dir);
    info_fp = fopen(info_file, "w");
    if (info_fp) {
        fprintf(info_fp, "Cursor File: %s\n", input_file);
        fprintf(info_fp, "Number of frames: %d\n", images->nimage);
        fprintf(info_fp, "\n");
        fprintf(info_fp, "Frame Details:\n");
        fprintf(info_fp, "Frame\tSize\tWidth\tHeight\tXHot\tYHot\tDelay\n");
        
        for (i = 0; i < images->nimage; i++) {
            XcursorImage *img = images->images[i];
            fprintf(info_fp, "%d\t%dx%d\t%d\t%d\t%d\t%d\t%d\n", 
                    i + 1, img->size, img->size, img->width, img->height, 
                    img->xhot, img->yhot, img->delay);
        }
        
        if (comments && comments->ncomment > 0) {
            fprintf(info_fp, "\nComments:\n");
            for (i = 0; i < comments->ncomment; i++) {
                fprintf(info_fp, "Type %d: %s\n", 
                        comments->comments[i]->comment_type,
                        comments->comments[i]->comment);
            }
        }
        
        fclose(info_fp);
    }
    
    /* Extract each frame */
    for (i = 0; i < images->nimage; i++) {
        snprintf(output_path, sizeof(output_path), "%s/frame_%03d.png", output_dir, i + 1);
        
        if (save_frame_as_png(images->images[i], output_path, i + 1) != 0) {
            fprintf(stderr, "Error: Failed to save frame %d\n", i + 1);
            XcursorImagesDestroy(images);
            if (comments) XcursorCommentsDestroy(comments);
            return 1;
        }
        
        printf("Saved frame %d: %dx%d (size=%d, delay=%dms) -> %s\n", 
               i + 1, images->images[i]->width, images->images[i]->height,
               images->images[i]->size, images->images[i]->delay, output_path);
    }
    
    /* Clean up */
    XcursorImagesDestroy(images);
    if (comments) XcursorCommentsDestroy(comments);
    
    return 0;
}

int save_frame_as_png(XcursorImage *image, const char *filename, int frame_num)
{
    FILE *fp;
    png_structp png_ptr;
    png_infop info_ptr;
    png_bytep *row_pointers;
    int x, y;
    
    /* Open output file */
    fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot create '%s': %s\n", filename, strerror(errno));
        return 1;
    }
    
    /* Initialize PNG structures */
    png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr) {
        fclose(fp);
        return 1;
    }
    
    info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_write_struct(&png_ptr, NULL);
        fclose(fp);
        return 1;
    }
    
    /* Set up error handling */
    if (setjmp(png_jmpbuf(png_ptr))) {
        png_destroy_write_struct(&png_ptr, &info_ptr);
        fclose(fp);
        return 1;
    }
    
    /* Set up PNG output */
    png_init_io(png_ptr, fp);
    
    /* Set PNG header */
    png_set_IHDR(png_ptr, info_ptr, image->width, image->height,
                 8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    
    /* Write PNG header */
    png_write_info(png_ptr, info_ptr);
    
    /* Allocate row pointers */
    row_pointers = (png_bytep*)malloc(sizeof(png_bytep) * image->height);
    for (y = 0; y < image->height; y++) {
        row_pointers[y] = (png_byte*)malloc(png_get_rowbytes(png_ptr, info_ptr));
    }
    
    /* Convert XCursor ARGB data to PNG RGBA data */
    for (y = 0; y < image->height; y++) {
        png_byte *row = row_pointers[y];
        for (x = 0; x < image->width; x++) {
            XcursorPixel pixel = image->pixels[y * image->width + x];
            
            /* XCursor uses pre-multiplied alpha, we need to separate it */
            separate_alpha_pixel(&pixel);
            
#if __BYTE_ORDER == __LITTLE_ENDIAN
            /* XCursor format: ARGB (little-endian) */
            row[x * 4 + 0] = (pixel >> 16) & 0xFF;  /* R */
            row[x * 4 + 1] = (pixel >> 8) & 0xFF;   /* G */
            row[x * 4 + 2] = pixel & 0xFF;          /* B */
            row[x * 4 + 3] = (pixel >> 24) & 0xFF;  /* A */
#else
            /* Big-endian systems */
            row[x * 4 + 0] = (pixel >> 8) & 0xFF;   /* R */
            row[x * 4 + 1] = (pixel >> 16) & 0xFF;  /* G */
            row[x * 4 + 2] = (pixel >> 24) & 0xFF;  /* B */
            row[x * 4 + 3] = pixel & 0xFF;          /* A */
#endif
        }
    }
    
    /* Write PNG data */
    png_write_image(png_ptr, row_pointers);
    png_write_end(png_ptr, NULL);
    
    /* Clean up */
    for (y = 0; y < image->height; y++) {
        free(row_pointers[y]);
    }
    free(row_pointers);
    
    png_destroy_write_struct(&png_ptr, &info_ptr);
    fclose(fp);
    
    return 0;
}

void separate_alpha_pixel(XcursorPixel *pixel)
{
    unsigned int alpha, red, green, blue;
    
    /* Extract components (XCursor format is ARGB) */
#if __BYTE_ORDER == __LITTLE_ENDIAN
    blue  = (*pixel) & 0xFF;
    green = ((*pixel) >> 8) & 0xFF;
    red   = ((*pixel) >> 16) & 0xFF;
    alpha = ((*pixel) >> 24) & 0xFF;
#else
    alpha = (*pixel) & 0xFF;
    red   = ((*pixel) >> 8) & 0xFF;
    green = ((*pixel) >> 16) & 0xFF;
    blue  = ((*pixel) >> 24) & 0xFF;
#endif
    
    /* If alpha is 0, pixel is fully transparent */
    if (alpha == 0) {
        *pixel = 0;
        return;
    }
    
    /* Separate pre-multiplied alpha (same algorithm as GIMP uses) */
    red   = (red * 255 + alpha / 2) / alpha;
    green = (green * 255 + alpha / 2) / alpha;
    blue  = (blue * 255 + alpha / 2) / alpha;
    
    /* Clamp values */
    if (red > 255) red = 255;
    if (green > 255) green = 255;
    if (blue > 255) blue = 255;
    
    /* Reconstruct pixel */
#if __BYTE_ORDER == __LITTLE_ENDIAN
    *pixel = blue | (green << 8) | (red << 16) | (alpha << 24);
#else
    *pixel = alpha | (red << 8) | (green << 16) | (blue << 24);
#endif
}

int create_directory(const char *path)
{
    struct stat st = {0};
    
    /* Check if directory already exists */
    if (stat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            return 0; /* Directory exists */
        } else {
            fprintf(stderr, "Error: '%s' exists but is not a directory\n", path);
            return 1;
        }
    }
    
    /* Create directory */
    if (mkdir(path, 0755) != 0) {
        fprintf(stderr, "Error: Cannot create directory '%s': %s\n", 
                path, strerror(errno));
        return 1;
    }
    
    return 0;
}

void print_usage(const char *program_name)
{
    printf("XCursor Frame Extractor\n");
    printf("Usage: %s <input_cursor_file> <output_directory>\n", program_name);
    printf("\n");
    printf("Extracts all frames from an XCursor file and saves them as PNG images.\n");
    printf("\n");
    printf("Example:\n");
    printf("  %s /usr/share/icons/Adwaita/cursors/left_ptr ./extracted_frames/\n", program_name);
    printf("\n");
    printf("Output files:\n");
    printf("  frame_001.png, frame_002.png, ... - Individual cursor frames\n");
    printf("  cursor_info.txt - Metadata about the cursor\n");
}
