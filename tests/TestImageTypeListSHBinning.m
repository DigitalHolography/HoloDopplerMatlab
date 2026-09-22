classdef TestImageTypeListSHBinning < matlab.unittest.TestCase

methods (Test)
    function dividesBothSpatialDimensionsBy16(testCase)
        list = ImageTypeList();
        list.select('SH');
        p = TestImageTypeListSHBinning.params(16);
        SHin = complex(ones(33,50,8,'single'));
        list.construct_image(p, SHin);
        testCase.verifySize(list.SH.parameters.SH, [2 3 8]);
        testCase.verifyEqual(list.SH.parameters.crop_size, [32 48]);
        testCase.verifyEqual(list.SH.parameters.spatial_binning, [16 16]);
        testCase.verifyEqual(list.SH.parameters.reduction, 'block_mean_power');
    end

    function preservesConstantPowerAndFrequencyAxis(testCase)
        list = ImageTypeList();
        list.select('SH');
        p = TestImageTypeListSHBinning.params(16);
        SHin = complex(2*ones(32,48,8,'single'));
        list.construct_image(p, SHin);
        testCase.verifyEqual(list.SH.parameters.SH, 4*ones(2,3,8,'single'));
        testCase.verifyEqual(numel(list.SH.parameters.vector), 8);
    end

    function computesBlockMeansNotDecimation(testCase)
        list = ImageTypeList();
        list.select('SH');
        p = TestImageTypeListSHBinning.params(2);
        power = single(reshape(1:32,4,4,2));
        SHin = complex(sqrt(power));
        list.construct_image(p, SHin);
        expected = zeros(2,2,2,'single');
        for k = 1:2
            for row = 1:2
                for col = 1:2
                    block = power((row-1)*2+(1:2), (col-1)*2+(1:2), k);
                    expected(row,col,k) = mean(block,'all');
                end
            end
        end
        testCase.verifyEqual(list.SH.parameters.SH, expected, 'AbsTol', single(2e-5));
    end

    function factorOneLeavesSHUnchanged(testCase)
        list = ImageTypeList();
        list.select('SH');
        p = TestImageTypeListSHBinning.params(1);
        SHin = complex(rand(5,7,4,'single'));
        list.construct_image(p, SHin);
        testCase.verifyEqual(list.SH.parameters.SH, abs(SHin).^2);
        testCase.verifyEqual(list.SH.parameters.binned_size, [5 7 4]);
    end

    function SHAverageUsesBinnedCube(testCase)
        list = ImageTypeList();
        list.select('SH','SH_avg');
        p = TestImageTypeListSHBinning.params(2);
        SHin = complex(rand(4,6,4,'single'));
        list.construct_image(p, SHin);
        expected = mean(list.SH.parameters.SH,3);
        testCase.verifyEqual(list.SH_avg.parameters.SH, expected, 'AbsTol', single(2e-6));
        testCase.verifySize(list.SH_avg.parameters.SH,[2 3]);
    end
end

methods (Static, Access=private)
    function p = params(factor)
        p = struct;
        p.frequencyRange1 = 1;
        p.frequencyRange2 = 4;
        p.frequencyRangeBandRatio1 = 1;
        p.frequencyRangeBandRatio2 = 2;
        p.fs = 8;
        p.flatfield_gw = 0;
        p.CornerCompensation = false;
        p.registrationDiskRatio = 0.8;
        p.bucketsRanges = [-1 -1];
        p.spatialTransform = 'Fresnel';
        p.SHSpatialBinning = factor;
    end
end
end
