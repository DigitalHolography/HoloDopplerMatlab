function SH = intercorrel(H, sub_size)

[width, height, ~] = size(H);
Lx = (1:sub_size:width);
Ly = (1:sub_size:height);

for ii = 1:(length(Lx) - 1)

    for kk = 1:(length(Ly) - 1)
        H1 = H(round(Lx(ii)):round(Lx(ii + 1) - 1), round(Ly(kk)):round(Ly(kk + 1) - 1), :);
        SH1 = intercorrel_with_middle(H1);
        SH(round(Lx(ii)):round(Lx(ii + 1) - 1), round(Ly(kk)):round(Ly(kk + 1) - 1), :) = SH1;
    end

end

function SH1 = intercorrel_with_middle(H1)
    [wi, hi, bs] = size(H1);
    middle = ceil([wi / 2 hi / 2]);
    SH1 = zeros([wi, hi, bs * 2 - 1], 'single');

    for l = 1:wi

        for m = 1:hi

            if m >= l && m ~= middle(2)
                SH1(l, m, :) = xcorr(squeeze(H1(l, m, :)), squeeze(H1(middle(1), middle(2), :)), 'normalized');
            elseif m == l && m == middle(1)
                SH1(l, m, :) = xcorr(H1(l, m)); % % auto corr
            elseif m < l
                SH1(l, m, :) = xcorr(squeeze(H1(l, m, :)), squeeze(H1(middle(1), middle(2), :)), 'normalized'); %SH1(m,l,:);
            end

        end

    end

end

end
