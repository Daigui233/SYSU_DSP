function make_stream_vectors
% Deterministic full-range complex frames, packed sample zero in the low byte.
    rng(7214, 'twister');
    file = fopen(fullfile(fileparts(mfilename('fullpath')), 'stream_vectors.svh'), 'w');
    assert(file >= 0);
    cleanup = onCleanup(@() fclose(file));
    count = 48;
    fprintf(file, 'localparam integer STREAM_COUNT = %d;\n', count);
    for n = [32 64]
        frames = randi([-128 127], count, n, 2);
        roots = exp((-2i*pi/n) * ((0:n-1).' * (0:n-1))) / n;
        peak = 0;
        for k = 1:count
            re = frames(k,:,1); im = frames(k,:,2);
            [yr, yi] = fft_fixed_reference(re, im);
            frames(k,:,3) = yr; frames(k,:,4) = yi;
            delta = complex(double(yr),double(yi)) - complex(re,im)*roots;
            peak = max([peak abs(real(delta)) abs(imag(delta))]);
        end
        fprintf('FFT%d max component error over %d frames: %.8f LSB\n', n, count, peak);
        names = {'IN_RE','IN_IM','OUT_RE','OUT_IM'};
        for field = 1:4
            fprintf(file, 'localparam logic [%d:0] F%d_%s [0:STREAM_COUNT-1] = ''{\n', ...
                    8*n-1, n, names{field});
            for k = 1:count
                bytes = mod(frames(k,end:-1:1,field),256);
                fprintf(file, '    %d''h%s', 8*n, sprintf('%02X', bytes));
                if k < count, fprintf(file, ',\n'); else, fprintf(file, '};\n'); end
            end
        end
    end
end
