%% Step3_final.m - パターン一致度計算（外れ値分析付き）
% 修正点：
% 1. 同一カテゴリペア同士を比較するよう実装
% 2. 外れ値分析（IQR法）を追加
% 3. 全店舗 vs 外れ値除去後の両方を報告

%% 1. データ読み込み
if ~exist('rawData_dailySales', 'var')
    error('rawData_dailySales が見つかりません。rawData.matを先に読み込んでください。');
end

try %[output:group:64247d64]
    load('step1_results.mat', 'analysisData');
    fprintf('✓ Step 1の結果を読み込みました\n'); %[output:387ac074]
catch
    error('step1_results.mat が見つかりません。');
end %[output:group:64247d64]

%% 2. TOP10カテゴリの取得
if isfield(analysisData, 'top10Categories') %[output:group:4a1d0fe0]
    uniqueCategories = analysisData.top10Categories;
    globalSalesMatrix = analysisData.top10SalesMatrix;
    fprintf('✓ TOP10カテゴリを使用します\n'); %[output:50585b4a]
else
    uniqueCategories = analysisData.categoryStats.MajorCategory(1:10);
    top10Idx = false(size(analysisData.salesMatrix, 1), 1);
    for i = 1:length(uniqueCategories)
        top10Idx = top10Idx | (analysisData.uniqueCategories == uniqueCategories(i));
    end
    globalSalesMatrix = analysisData.salesMatrix(top10Idx, :);
    fprintf('✓ categoryStatsからTOP10カテゴリを取得しました\n');
end %[output:group:4a1d0fe0]

nCategories = length(uniqueCategories);
nDates = size(globalSalesMatrix, 2);
fprintf('カテゴリ数: %d, 日数: %d\n', nCategories, nDates); %[output:80f02683]

%% 3. 基準パターン（相関行列）
globalCorrMatrix = corrcoef(globalSalesMatrix');
fprintf('✓ 基準パターン（相関行列）を計算しました\n'); %[output:546be7a3]

%% 4. 店舗リストの取得
storeList = unique(rawData_dailySales.BookstoreCode);
nStores = length(storeList);
fprintf('店舗数: %d店舗\n', nStores); %[output:8c074b5a]

%% 5. 店舗別データ集計
fprintf('店舗別データを集計中...\n'); %[output:078ede72]
storeDailyCategorySales = grpstats(rawData_dailySales, ...
    {'BookstoreCode', 'Date', 'MajorCategory'}, ...
    'sum', 'DataVars', 'POSSalesVolume');
fprintf('集計完了: %d レコード\n', height(storeDailyCategorySales)); %[output:8c05ede9]

%% 6. 店舗別相関行列の計算
storeCorrMatrices = nan(nCategories, nCategories, nStores);
storeValidFlags = false(nStores, 1);
storeTotalSales = zeros(nStores, 1);
minValidDays = 30;

uniqueDates = analysisData.uniqueDates;

for s = 1:nStores
    storeCode = storeList(s);
    storeData = storeDailyCategorySales(storeDailyCategorySales.BookstoreCode == storeCode, :);
    
    if isempty(storeData)
        continue;
    end
    
    storeTotalSales(s) = sum(storeData.sum_POSSalesVolume);
    storeSalesMatrix = zeros(nCategories, nDates);
    
    for i = 1:height(storeData)
        catIdx = find(uniqueCategories == storeData.MajorCategory(i));
        if ~isempty(catIdx)
            dateIdx = find(uniqueDates == storeData.Date(i));
            if ~isempty(dateIdx)
                storeSalesMatrix(catIdx, dateIdx) = storeData.sum_POSSalesVolume(i);
            end
        end
    end
    
    validDays = sum(storeSalesMatrix > 0, 1) >= ceil(nCategories / 2);
    nValidDays = sum(validDays);
    
    if nValidDays >= minValidDays
        validData = storeSalesMatrix(:, validDays);
        validCats = std(validData, 0, 2) > 0;
        
        if sum(validCats) >= ceil(nCategories / 2)
            fullCorrMat = nan(nCategories, nCategories);
            validCorrMat = corrcoef(validData(validCats, :)');
            validIdx = find(validCats);
            for ii = 1:length(validIdx)
                for jj = 1:length(validIdx)
                    fullCorrMat(validIdx(ii), validIdx(jj)) = validCorrMat(ii, jj);
                end
            end
            storeCorrMatrices(:, :, s) = fullCorrMat;
            storeValidFlags(s) = true;
        end
    end
end

nValidStores = sum(storeValidFlags);
fprintf('有効店舗数: %d / %d\n', nValidStores, nStores); %[output:7fd52915]

%% 7. パターン一致度の計算
patternSimilarity = nan(nStores, 1);
upperTriIdx = triu(true(nCategories), 1);
globalVec = globalCorrMatrix(upperTriIdx);

for s = 1:nStores
    if ~storeValidFlags(s)
        continue;
    end
    
    storeCorrMat = storeCorrMatrices(:, :, s);
    storeVec = storeCorrMat(upperTriIdx);
    validPairs = ~isnan(globalVec) & ~isnan(storeVec);
    
    if sum(validPairs) >= 10
        r = corrcoef(globalVec(validPairs), storeVec(validPairs));
        patternSimilarity(s) = r(1, 2);
    end
end

%% 8. 全店舗での相関分析
validStoreIdx = find(~isnan(patternSimilarity));
nValidForCorr = length(validStoreIdx);

validSimilarity = patternSimilarity(validStoreIdx);
validSales = storeTotalSales(validStoreIdx);

[r_all, p_all] = corrcoef(validSimilarity, validSales);
fprintf('\n=== パターン一致度 vs 総販売冊数（全店舗）===\n'); %[output:7a5c43a3]
fprintf('  相関係数 r = %.3f\n', r_all(1,2)); %[output:3a4262d8]
fprintf('  p値 = %.4f\n', p_all(1,2)); %[output:60f70970]
fprintf('  有効店舗数 n = %d\n', nValidForCorr); %[output:19b38a68]

%% 9. 外れ値分析（IQR法）
Q1 = prctile(validSimilarity, 25);
Q3 = prctile(validSimilarity, 75);
IQR_val = Q3 - Q1;
lowerBound = Q1 - 1.5 * IQR_val;
upperBound = Q3 + 1.5 * IQR_val;

fprintf('\n=== 外れ値判定（IQR法）===\n'); %[output:0e63991a]
fprintf('Q1 = %.3f, Q3 = %.3f, IQR = %.3f\n', Q1, Q3, IQR_val); %[output:2e26a5d5]
fprintf('下限 = %.3f, 上限 = %.3f\n', lowerBound, upperBound); %[output:93f56c14]

% 外れ値フラグ
outlierFlags = (patternSimilarity < lowerBound | patternSimilarity > upperBound) & ~isnan(patternSimilarity);
outlierIdx = find(outlierFlags);
nOutliers = length(outlierIdx);

fprintf('\n外れ値の数: %d\n', nOutliers); %[output:95160578]
if nOutliers > 0 %[output:group:8faf6b95]
    fprintf('外れ値の店舗:\n'); %[output:508a734a]
    for i = 1:nOutliers
        fprintf('  店舗%d: 一致度 = %.3f, 総販売冊数 = %.0f\n', ... %[output:388a17d9]
            storeList(outlierIdx(i)), patternSimilarity(outlierIdx(i)), storeTotalSales(outlierIdx(i))); %[output:388a17d9]
    end
end %[output:group:8faf6b95]

%% 10. 外れ値除去後の相関分析
noOutlierIdx = find(~isnan(patternSimilarity) & ~outlierFlags);
nNoOutlier = length(noOutlierIdx);

[r_noOutlier, p_noOutlier] = corrcoef(patternSimilarity(noOutlierIdx), storeTotalSales(noOutlierIdx));

fprintf('\n=== パターン一致度 vs 総販売冊数（外れ値除去後）===\n'); %[output:5f2ae49e]
fprintf('  相関係数 r = %.3f（除去前: %.3f）\n', r_noOutlier(1,2), r_all(1,2)); %[output:30d891a4]
fprintf('  p値 = %.4f\n', p_noOutlier(1,2)); %[output:15d9d1d3]
fprintf('  有効店舗数 n = %d（除去前: %d）\n', nNoOutlier, nValidForCorr); %[output:91b88fdc]
fprintf('  変化率: %.1f%%\n', (r_noOutlier(1,2) - r_all(1,2)) / r_all(1,2) * 100); %[output:20f7a59f]

%% 11. 典型店舗・異質店舗
[maxSim, maxIdx] = max(patternSimilarity);
[minSim, minIdx] = min(patternSimilarity);

fprintf('\n=== 典型店舗・異質店舗 ===\n'); %[output:72df415f]
fprintf('典型店舗: 店舗%d（一致度: %.3f）\n', storeList(maxIdx), maxSim); %[output:816e3ac7]
fprintf('異質店舗: 店舗%d（一致度: %.3f）%s\n', storeList(minIdx), minSim, ... %[output:group:3e4e65d0] %[output:124a26da]
    iif(outlierFlags(minIdx), ' ※外れ値', '')); %[output:group:3e4e65d0] %[output:124a26da]

%% 12. 可視化
figure('Position', [100, 100, 1400, 500]); %[output:2298f8b9]
sgtitle('Step 3: 店舗間比較分析（上位10カテゴリ）'); %[output:2298f8b9]

% (a) パターン一致度のランキング
subplot(1, 3, 1); %[output:2298f8b9]
[sortedSim, sortIdx] = sort(patternSimilarity, 'descend');
validSortIdx = sortIdx(~isnan(sortedSim));
validSortedSim = sortedSim(~isnan(sortedSim));

barColors = repmat([0.3 0.6 0.9], length(validSortIdx), 1);
for i = 1:length(validSortIdx)
    if outlierFlags(validSortIdx(i))
        barColors(i, :) = [0.9 0.3 0.3];  % 外れ値は赤
    end
end

for i = 1:length(validSortIdx)
    barh(i, validSortedSim(i), 'FaceColor', barColors(i,:)); %[output:2298f8b9]
    hold on;
end
hold off; %[output:2298f8b9]
yticks(1:length(validSortIdx)); %[output:2298f8b9]
yticklabels(arrayfun(@(x) sprintf('店舗%d', storeList(x)), validSortIdx, 'UniformOutput', false)); %[output:2298f8b9]
xlabel('パターン一致度'); %[output:2298f8b9]
title(sprintf('パターン一致度ランキング\n（赤: 外れ値, n=%d）', nValidForCorr)); %[output:2298f8b9]
set(gca, 'YDir', 'reverse'); %[output:2298f8b9]
xline(lowerBound, 'r--', 'LineWidth', 1); %[output:2298f8b9]
grid on; %[output:2298f8b9]

% (b) 箱ひげ図
subplot(1, 3, 2); %[output:2298f8b9]
boxplot(validSimilarity); %[output:2298f8b9]
hold on; %[output:2298f8b9]
scatter(ones(nOutliers, 1), patternSimilarity(outlierIdx), 80, 'r', 'filled', 'd'); %[output:2298f8b9]
hold off; %[output:2298f8b9]
ylabel('パターン一致度'); %[output:2298f8b9]
title(sprintf('分布（外れ値: %d店舗）', nOutliers)); %[output:2298f8b9]
grid on; %[output:2298f8b9]

% (c) 一致度 vs 総販売冊数（外れ値ハイライト）
subplot(1, 3, 3); %[output:2298f8b9]
normalIdx = find(~outlierFlags & ~isnan(patternSimilarity));
scatter(patternSimilarity(normalIdx), storeTotalSales(normalIdx)/1000, 50, 'b', 'filled'); %[output:2298f8b9]
hold on; %[output:2298f8b9]
if nOutliers > 0
    scatter(patternSimilarity(outlierIdx), storeTotalSales(outlierIdx)/1000, 80, 'r', 'filled', 'd'); %[output:2298f8b9]
end
% 回帰直線（全データ）
p_fit_all = polyfit(validSimilarity, validSales/1000, 1);
x_line = linspace(min(validSimilarity), max(validSimilarity), 100);
plot(x_line, polyval(p_fit_all, x_line), 'b-', 'LineWidth', 1.5); %[output:2298f8b9]
% 回帰直線（外れ値除去後）
p_fit_no = polyfit(patternSimilarity(noOutlierIdx), storeTotalSales(noOutlierIdx)/1000, 1);
x_line2 = linspace(min(patternSimilarity(noOutlierIdx)), max(patternSimilarity(noOutlierIdx)), 100);
plot(x_line2, polyval(p_fit_no, x_line2), 'g--', 'LineWidth', 1.5); %[output:2298f8b9]
hold off; %[output:2298f8b9]
xlabel('パターン一致度'); %[output:2298f8b9]
ylabel('総販売冊数（千冊）'); %[output:2298f8b9]
legend({'通常店舗', '外れ値', sprintf('全店舗 r=%.3f', r_all(1,2)), sprintf('除去後 r=%.3f', r_noOutlier(1,2))}, ... %[output:2298f8b9]
    'Location', 'northwest'); %[output:2298f8b9]
title(sprintf('一致度 vs 販売冊数\n全店舗: r=%.3f (p=%.3f)\n除去後: r=%.3f (p=%.3f)', ... %[output:2298f8b9]
    r_all(1,2), p_all(1,2), r_noOutlier(1,2), p_noOutlier(1,2))); %[output:2298f8b9]
grid on; %[output:2298f8b9]

%% 13. 相関行列比較の可視化
figure('Position', [100, 100, 1400, 350]); %[output:447f9930]
sgtitle('相関行列の比較（上位10カテゴリ）'); %[output:447f9930]

catLabels = cellstr(uniqueCategories);
for i = 1:length(catLabels)
    if length(catLabels{i}) > 6
        catLabels{i} = catLabels{i}(1:6);
    end
end

subplot(1, 3, 1); %[output:447f9930]
imagesc(globalCorrMatrix); %[output:447f9930]
colormap('jet'); colorbar; caxis([-1, 1]); %[output:447f9930]
title('全体パターン（基準）'); %[output:447f9930]
xticks(1:nCategories); yticks(1:nCategories); %[output:447f9930]
xticklabels(catLabels); yticklabels(catLabels); %[output:447f9930]
xtickangle(45); %[output:447f9930]

subplot(1, 3, 2); %[output:447f9930]
imagesc(storeCorrMatrices(:, :, maxIdx)); %[output:447f9930]
colormap('jet'); colorbar; caxis([-1, 1]); %[output:447f9930]
title(sprintf('典型店舗（店舗%d, 一致度%.3f）', storeList(maxIdx), maxSim)); %[output:447f9930]
xticks(1:nCategories); yticks(1:nCategories); %[output:447f9930]
xticklabels(catLabels); yticklabels(catLabels); %[output:447f9930]
xtickangle(45); %[output:447f9930]

subplot(1, 3, 3); %[output:447f9930]
imagesc(storeCorrMatrices(:, :, minIdx)); %[output:447f9930]
colormap('jet'); colorbar; caxis([-1, 1]); %[output:447f9930]
title(sprintf('異質店舗（店舗%d, 一致度%.3f）※外れ値', storeList(minIdx), minSim)); %[output:447f9930]
xticks(1:nCategories); yticks(1:nCategories); %[output:447f9930]
xticklabels(catLabels); yticklabels(catLabels); %[output:447f9930]
xtickangle(45); %[output:447f9930]

%% 14. 結果の保存
step3Results = struct();
step3Results.globalCorrMatrix = globalCorrMatrix;
step3Results.storeCorrMatrices = storeCorrMatrices;
step3Results.patternSimilarity = patternSimilarity;
step3Results.storeValidFlags = storeValidFlags;
step3Results.storeTotalSales = storeTotalSales;
step3Results.storeList = storeList;

% 全店舗の結果
step3Results.all.nValid = nValidForCorr;
step3Results.all.r = r_all(1,2);
step3Results.all.p = p_all(1,2);
% 
% 外れ値情報
step3Results.outlier.flags = outlierFlags;
step3Results.outlier.idx = outlierIdx;
step3Results.outlier.nOutliers = nOutliers;
step3Results.outlier.lowerBound = lowerBound;
step3Results.outlier.upperBound = upperBound;

% 外れ値除去後の結果
step3Results.noOutlier.idx = noOutlierIdx;
step3Results.noOutlier.nValid = nNoOutlier;
step3Results.noOutlier.r = r_noOutlier(1,2);
step3Results.noOutlier.p = p_noOutlier(1,2);

% 典型・異質店舗
step3Results.typicalStore = struct('idx', maxIdx, 'code', storeList(maxIdx), 'similarity', maxSim);
step3Results.atypicalStore = struct('idx', minIdx, 'code', storeList(minIdx), 'similarity', minSim, ...
    'isOutlier', outlierFlags(minIdx));

save('step3_results.mat', 'step3Results');
fprintf('\n✓ 結果を step3_results.mat に保存しました\n'); %[output:5a23041b]

%% ヘルパー関数
function result = iif(condition, trueVal, falseVal)
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end
%%


%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":40}
%---
%[output:387ac074]
%   data: {"dataType":"text","outputData":{"text":"✓ Step 1の結果を読み込みました\n","truncated":false}}
%---
%[output:50585b4a]
%   data: {"dataType":"text","outputData":{"text":"✓ TOP10カテゴリを使用します\n","truncated":false}}
%---
%[output:80f02683]
%   data: {"dataType":"text","outputData":{"text":"カテゴリ数: 10, 日数: 366\n","truncated":false}}
%---
%[output:546be7a3]
%   data: {"dataType":"text","outputData":{"text":"✓ 基準パターン（相関行列）を計算しました\n","truncated":false}}
%---
%[output:8c074b5a]
%   data: {"dataType":"text","outputData":{"text":"店舗数: 35店舗\n","truncated":false}}
%---
%[output:078ede72]
%   data: {"dataType":"text","outputData":{"text":"店舗別データを集計中...\n","truncated":false}}
%---
%[output:8c05ede9]
%   data: {"dataType":"text","outputData":{"text":"集計完了: 263409 レコード\n","truncated":false}}
%---
%[output:7fd52915]
%   data: {"dataType":"text","outputData":{"text":"有効店舗数: 35 \/ 35\n","truncated":false}}
%---
%[output:7a5c43a3]
%   data: {"dataType":"text","outputData":{"text":"\n=== パターン一致度 vs 総販売冊数（全店舗）===\n","truncated":false}}
%---
%[output:3a4262d8]
%   data: {"dataType":"text","outputData":{"text":"  相関係数 r = 0.517\n","truncated":false}}
%---
%[output:60f70970]
%   data: {"dataType":"text","outputData":{"text":"  p値 = 0.0015\n","truncated":false}}
%---
%[output:19b38a68]
%   data: {"dataType":"text","outputData":{"text":"  有効店舗数 n = 35\n","truncated":false}}
%---
%[output:0e63991a]
%   data: {"dataType":"text","outputData":{"text":"\n=== 外れ値判定（IQR法）===\n","truncated":false}}
%---
%[output:2e26a5d5]
%   data: {"dataType":"text","outputData":{"text":"Q1 = 0.621, Q3 = 0.830, IQR = 0.208\n","truncated":false}}
%---
%[output:93f56c14]
%   data: {"dataType":"text","outputData":{"text":"下限 = 0.309, 上限 = 1.142\n","truncated":false}}
%---
%[output:95160578]
%   data: {"dataType":"text","outputData":{"text":"\n外れ値の数: 2\n","truncated":false}}
%---
%[output:508a734a]
%   data: {"dataType":"text","outputData":{"text":"外れ値の店舗:\n","truncated":false}}
%---
%[output:388a17d9]
%   data: {"dataType":"text","outputData":{"text":"  店舗26: 一致度 = 0.223, 総販売冊数 = 8438\n  店舗27: 一致度 = 0.034, 総販売冊数 = 12155\n","truncated":false}}
%---
%[output:5f2ae49e]
%   data: {"dataType":"text","outputData":{"text":"\n=== パターン一致度 vs 総販売冊数（外れ値除去後）===\n","truncated":false}}
%---
%[output:30d891a4]
%   data: {"dataType":"text","outputData":{"text":"  相関係数 r = 0.322（除去前: 0.517）\n","truncated":false}}
%---
%[output:15d9d1d3]
%   data: {"dataType":"text","outputData":{"text":"  p値 = 0.0674\n","truncated":false}}
%---
%[output:91b88fdc]
%   data: {"dataType":"text","outputData":{"text":"  有効店舗数 n = 33（除去前: 35）\n","truncated":false}}
%---
%[output:20f7a59f]
%   data: {"dataType":"text","outputData":{"text":"  変化率: -37.7%\n","truncated":false}}
%---
%[output:72df415f]
%   data: {"dataType":"text","outputData":{"text":"\n=== 典型店舗・異質店舗 ===\n","truncated":false}}
%---
%[output:816e3ac7]
%   data: {"dataType":"text","outputData":{"text":"典型店舗: 店舗23（一致度: 0.922）\n","truncated":false}}
%---
%[output:124a26da]
%   data: {"dataType":"text","outputData":{"text":"異質店舗: 店舗27（一致度: 0.034） ※外れ値\n","truncated":false}}
%---
%[output:2298f8b9]
%   data: {"dataType":"image","outputData":{"dataUri":"data:image\/png;base64,iVBORw0KGgoAAAANSUhEUgAAAVcAAAB7CAYAAADAKMPhAAAQAElEQVR4AezdCZxkVXUG8HsnEkBFcImYqDioIAQVCFFZQmyiCMg2RlCIC01cIJHIqHHDKIOKEbcIQpS4MKIJGFGRRSWIDDGAOyBqxA1QUNwIioiIQur\/Zk5z+82r6qruVzXdMzW\/OX3vu\/v63XPOXWrRfe5znzvHNG6D8RgYj4HxGGh3DCxK43\/jFhi3wLgFxi3QeguMwbX1Jh0nOG6BcQusUy3QpbJjcO3SMGPnda8F7n73u6e73e1u617F12CN22zzNtNqo0nG4NpGK3bSeN7znpc+8YlPpKc85Smdr+7\/N9544\/Sv\/\/qvVdi\/\/\/u\/Xy3gP\/zDP6Tzzz8\/\/fM\/\/3MVbsstt6zCmPTbbrttetzjHjeNuN3znvdMf\/ZnfzbNXTh+4lUJdP4cc8wx6cwzz6zCdj6n\/r\/zne9Mp556atpss82m3Jos6tgUX1jlvuiii9LTnvY0n13p2c9+dnrJS16S\/viP\/7gKs8kmmyRxDzzwwOq76Y+6yVf+Tf7c\/uIv\/iL9y7\/8Szr44IN9DkzaWRv827\/9W7r\/\/e\/fGH9iYiK9613vSk996lMb\/Zscled973tfEjf8jRH1YYbbsE3jwHhA7MPOr1f6j3zkI9NrXvOatN9++6UPfehD6elPf3qv4H35PfGJT0xnnHFGOvLII\/sKP4pAY3BtqZU32GCDdI973COtt956PVM0of70T\/803XrrrRUQveAFL2gM\/9\/\/\/d9Vesd0APFBD3pQevCDH1wNyOOOOy69\/vWvr4jdIN15550TO6r7iRcZrL\/++lWa9TJa8ZX9D\/7gDyLolGkxeM5znlMB4qMf\/egEDPfZZ5\/qe6eddpoK149l8803T\/vvv3\/6y7\/8y\/RHf\/RHVRRAtvvuu1egCOAqx9of5VU+bRxer33taxNavnx5+vSnP53e\/OY3px122CE94QlPSCZvhOvHBDaAWzsA2J\/85CeN0ZR16623Tn\/yJ3\/S6F931HYm\/f3ud7\/0wx\/+cMo76sOcchyyxTgwVhB7P9lFP1sMu9EznvGMfpKaFua6665Lj3jEI5K2ueyyy9KSJUuSsRGBttpqq\/SOd7wjvfGNb0wPeMADwrky9e2HP\/zh1ZgBY8Cc2XvvvauxVAVu\/c9gCS4aLPjsQmukSy+9NAU1cTg4rZm4ntnlPj0WLqlXOaaHXv3LIPjIRz4yVZdI62\/+5m\/SH\/7hH6YXvehFq\/nhRNUPOAHX733vexU4ffe73004NhNaGMTfJH\/xi19cTWIT9DGPecxUQb761a+mf\/qnf6qIfcqjY\/Hdza\/jPav\/nR3k9OQnPzkdcMAB6c\/\/\/M8TgN5rr72q78MPP3yqrvX6N\/UxDsVk0WbKqkDf+ta30jnnnJMA0BFHHNG3WP6Qhzyk4gZx7V\/60pcqTh8n9NznPjd97Wtfk3TfpH6A2eRcsWJF3\/FmCqgvH\/7wh6dLLrkkqedM4Zv8zZ33v\/\/9q3mZKxdddNFU+wu3WqA5OpAG9HsvetKTnrRaLvrYPFnNY5XDTTfdlMyh3\/3ud+k\/\/uM\/0jEdBuLqq69e5ZuSMQ9gSTc33HDDlDvLLbfckhYtWlQxCXVmQDtZGC3g4gq\/Jmno4KrCW2yxRTL5cDoI+w6EAJ3KAx4c16abbupzaCQ\/A4X4GOXAsch\/0Ey\/\/e1vV2KIugRdfvnl6fIOxXeYH\/vYxyrQwDXgVq655pr09re\/vRKJvvOd76TPfe5z6VOf+lRFX\/\/619Ptt9+ePvvZz1bf\/\/Vf\/5XkFeUD0NoKsYc70zd3xM5tNoQ7AAziGvTEYO1lIvzqV79KS5cuTb6JyB\/96EfTFVdckS644IKqPQDUl7\/85aTO3\/jGNyRREfF4zz33TD\/4wQ+SMVE5rvpDbFbv7bbbbppYJ9\/3vve9CXev3R7\/+Mcn39xF\/elPf5pe+tKXple84hXprLPOSiYt90EJuKqXugwat1t4XDjO7xe\/+EUF9hZOiwoy9i0KTN9BxmeZHsBU59KN3Xg1bsXTDzGey\/j6UD8Fx2lh23DDDRNiD3emfsG9S7sk7Sr9XnTIIYeUUSo7hsFYUb5upN8e+9jHpl133bVqnyriHP\/86Ec\/qlRqJIy\/+qu\/mmNqc48+VHA1CIhQuAGTNIqL5beS44TCbRSm\/HT2f\/7nf1bZ4Zh++ctfJp1cOQzwh5j31re+NZWE40SlGzsd6+c\/\/\/n0zW9+M\/3v\/\/5vJRJv0tE17rjjjukrX\/lKJdbiQv7nf\/6nEh+t6Lgv3xdeeGEVL4oGiInRiD3cmb65I3Zudco5pwc+8IFT+llcRlr1D4C9\/OUvTyeeeGLCReIEeZnk2s0CCRQsDMpLvLz22mvTVh0xDogcf\/zx6c4770zUHtdff\/3UpJmYmEjPetazqkUDkJoE0g1SXwCB65AnMOWHa6YHVl5SQXwz+bdB22+\/faVrthAYk\/2mCYzoL41xRC+s78XnB\/yU20KpLSw2sdh2M3Hg4m\/eUZ\/g7IAa0OdWkoXPuD355JMrZ+NZ\/2hncTnqA+EwEwg3d+973zshdm5BQFS7i9cGEfs\/+clPVottr7r+\/ve\/T8ZNG3lGGqQEbaZPwm0WZitRhgquUUKDLOxhWvGQRsBpmbQm7\/vff5cIxG7QoIsuuqjSUUZ8E94APO2006ZEI98xuCJcacrPQCrd2KN84kpD2txnQ8QR3FVJOFYAgqOjs9tmm20q3axVm1hF9wSEgZZBTr9oZfctLhCLsuBktAdiD3emb+6InVudyrSlj8sQ5r73vW866aSTqk0G4PeWt7yl4gb5Ie0PAK\/pcN04IouLBYJ4+rOf\/ayaSOoIYIEk7lJb4N60uf7FjZtM+rxOJj0AAkbSfOUrX5lOOeWUZKHA9eWcK27Y97vf\/W5FqhYpdv4lUbMA5SrQDH\/0OVUHFc0MQae8jVN1wblrQ0Tf\/ahHPaqSUNTXgn3HHXdUcXDUuOIHdPSH8tLXQepNJaF99ZsI2ow5OTlZLbbsJWlXAFIyLBbpDTp6f1ybsCQeXKm+QvpOnMs7kpXvoC9+8YvVomcBEA\/pu3L89mMXR1ykH+nDo45N5iALmTT7JcwLiYaaiXqh33jDCDdUcMWtARQT3cAxAUyqsiLC0BPqeKIEADTggZxwVm9kBcTRmHjcEa74t7\/9bSWiGvDcli1bxuiLDjvssHSve92rmrQiGKwGicnhu20y6IigzF\/\/+teV3nTJkiUJOKm\/Aa8NSnu9DCaDcId39J3AWXlxuDhO7kHC1eP6prOy+RPhbA5wzzknKgrpEOFxHtyDcNnay0J07LHHVrv9FgaTGeACbWGVybfBPdHhWPU3rtPGhc0mQNSNcMsmPzCSBrA2QULFYRwRt+WDfvOb36RrO5wzVQM9HK75+9\/\/fgVIxoUwM5H+Fw\/ozxQ2\/HGYxmNJ+lTe6moD0gRXrohDd7jRRhtVm23qxJ350Ic+tNJj\/\/znP+dUEclOvxqPlUPxx9ywUFkAC+fKKm+6aB83dfSayml+IVw1f+3lO8g4FL4k8wrnOwiJU6axJu3a3iLWpoQzm\/oMFVwVCFCZyADDoDCxAC3wNFCEqZMNHKswcTr8DDgTzm5guEkzwhiIjnXo5BKAI2xp0k0pg8kK\/A200r+XHYcXQNIUzqC3u16SVVxYR54sMMQ1gx3H7huXI03fpR+7eCWZDMr713\/91wkAiv\/xj3+8Oi0gPiDiL1wZL+yABJciDDLp+QH4N73pTQlQ+66TDShg8uMf\/7g6IoY71Yc4IpMQtwUsmCb45ORkIlUc09mswB0fffTR1SaesXDxxRcn4IfD9I3oTLnpD8e1xFUGfUQXr9wmC\/DHMfOLtn7d616XgEl8G3NRL+F6EVUIYO4Vpu6H66pzY8ah\/LW7xcsYu+2226ZFNX7VwR4ED8CqLsDA+OU2LKK6IYZTN5V5GIfcUbibaxiaOuGu9ZE+r\/uJE\/GHacb8wySUi9ds8xxmvKGDq8KbxMS56BCdBAS7cZkmk0EYQAwIUcm1SJfeySRnR1ZlpvjMbmQgKAtu10CnfugWtu5uhxKZ7NIgegXhTFB8M4Es0JEOkRmXTuR1GoAdAS5cGFHTxg7ROOziNZGVOSayNAB3zjlZlJrCz9Vt8eLF1REqYuySJUuShdKExLEBDQsi9YZ+JaLSu8kT94krA37BSYnrKBru2thAFkrhpRlcJN2lNIGPuhoDRGLng6UhbXHmQvIivuvTuaRTxqViALSlG7vxqU7GnG8mcKPv9T0sMm8sgPrB4lXmY2wCKn6le5Pd8Tngqh5N\/m27GctUKWW6vnHgxkO3\/tem5qexVMYdtX0k4FqvFM4iAJbYWPcneppsOBoAVhK1QT38bL9xCzbbAEJTOZrSxWFyp3O0QUZ8I+rv2dkJB6yIHdGf8rNQiEPfioPDYQYBWkBhguMqpGvQhF28biTeQQcdlJ7\/\/OcngGfidgs7F3fcrP7C3cqD+oBOL0DBSQeTlNrA5HNyoFt+2ow+9MYbb5x2CqIpPI5XmwFhkwU3Si\/sRIJ+KBfWpvj9uOHihcNtM4dJ1AbSt0Awca4WUn3tux8yZs2NSKOMo+2bgM9ZVBzfF77whVSCPqACYDhs\/VGmVbfrB+BqMSrTqIdr49tiixlzqkGfl2k6HgZcL+\/ojkv3sKsT5ko5o73Db9TmUMHVxhCxtQm4YlA3VZifBpxpwNOX0flFGhGe6BpuYVJBEGOVKdxmYwIGYiSgEd\/ksGtrMNQJR1cO3BBBcaUAyekBIIFrYtrEAsilXR5rgoD\/2972tuo21x577FGdAIgJ7eymzRuqCWVzM82ktrDYrcW5cm+ifffdt+J6cbEmQISxoNbBwcafyVVyW+eee26SvyNFzgtH\/NmagA1I4+wsELNNp594uC11NGYtUjhKoBaLVD9pCAPcLKzGtG\/ktALpR118B9GfU62YE9RH4c7Un\/qMBFj2Bb86UcdhEmwYrSnQeuYzn5no\/tXlvPPOqxex+qZiswg4Hlg5xJ81YA4VXImM6vSyl71s2g0Mg2JiYiKZNFYpA0IHm2DCOyIFvKxcwnID0IC6BEcDjIjIXzjhcX6OpnAryYrvvCguOHSy0gRmUY4yfDc7AMdF9TvAgG85cIkqBgadHd1d5IMbwanPtKEV4ZninH766cmVzTPPPDPheLn3opxz2m233RI1AlDsphKxIWUhMVCdVmA3uSwQJqVvprxwrACP3eDeZZddWFcjG5L6XR+FTjUC0T1qK+ATbnapATwVQrgxHYEiytok8z0X0jeA3iaURWQuac0UFyhaWC0+2223XcJlAVYLyExxS3\/zCmOh3bkbz8Y1Kcw454ZcqEDsNi6NN+EArrHvMoh0lEuYbuRYGV061YF0uoULd3p2c7UXNe0nRPy6ubijknIaQzn40f2X9eSGLFjUSBYZizy3NUlDBVfAiZsDAkCDzgyxGwjUAyqvoQCfFRZ3ye0f\/\/EfGdUNDnHoX4FgxOFpkuJw+UtTPr3UBuIKG4e362kCpfYnNwAAEABJREFUaPmXAC6fIGDicLbFAMfDHddpoACCOgkvTEm4UlyhgSde6Teonf7TwiW9v\/u7v0tAX\/omTsmF2SCyYWRi8XfOkZhHDwqggJpJRnykJ6aqMKAtcBYCKgf9aFLjvuh4fdvYcBzJZKVntJFjgNOlm9Ts6qQ873nPe6qLJMCMzpseFUjyc+qAaubmm2+eJrYaF8onjSDgrOw45W6iYYTt11QvHCROXJ\/FODBWSjJujDe6+tI97PpUfer56md+H\/jAB5LD7UACWOgjV4H5IQtePW7Tt3nlCJr+lLdyMbVrhJeHs8W+hY3FzELppImxT4rA1Lg6KlydjAGLm3T0O5WM\/YF6uPq3\/YC6W7dv86ebH+bJ2LbxqZ2MV3Mz6lKPR41kflIbWTDr\/qP+Hiq4RmUAnoFQUjkQhAN8\/OkwTSrEzi1IGGFLOuqoo6qjWMLIp\/RrsktD2CDfES7yLN3Cj4nbAE4mPJDgRkVAzMPJ1alpkFlVcS\/UAjavpNFERCCTGCdX59yExzlbnYUDdMihcKcFTBxltdgADfEBnfpZhEwuICV9YelPc86J6CcN3Lzw3OXVRADuDW94Q7ILffbZZ1eXDpzlpFPWNqQI+mBgRScs\/JVXXpksmk4L4LLlJX+cDs6VTnAmLg6HqU0AojSayjaom3Zx0kQ\/evjDYmOxx1UOQtQ86l7PXx\/or5KojIRnhnsTB2lMo3qapDPMSNM4FhagAiIL3b\/\/+79zqkifGt8kFkRa0h+VZ+2PTUltQ8euX8WtBWn8lL7x2IuWL19eHf3Tl42JdByNX4synbuFxyJu3nS8VvsPVOHF1VdfXT2us1qANeAwEnBdA\/UaSpaOPhHBdLQMiEgvfOELq1eSmgYSsc3rVsIigxNX6IA+tYDjOuLhaHCDwEeajhvhAvnjSAGOYyeOdNHvSsvRH4OYn29kYr\/qVa+qrqcSwcXlJk0ba5OTk9WDGHV9lIlKnIqJyvQNLKUbJB1lU066NwubNHFhOBvhTAScsnp+8IMfrDhR\/oceemgC6kRT4RBOyORGAESbcK+T\/OQrf2nipLRlhIu2Kds6\/Po1pa1fP\/OZzyRtqm2d9BiE9BfAjDyVR58pcz\/pCBtx2zCNVwt5mRbuD5dL4kBlf5Th2C1emKC\/\/du\/TfqVW1uEG9UmJMVeaVp8SFPCxxhrCk\/\/bhwba+rYFGbUbmNwHbDFraZINJOQ+NGtM000JCwSDtdbHySluzTp5HAzZdoGOlDESUirG\/EnNkqjnk+3OP26R9kiXRPT4K\/H56\/s4S4ciu8wpaesSLnDvW5KT32E52fBYAZF25RtHX6DmAAWaEtvkHjdwiqPPmsrvW75jN1TMkaAa9M4W1Pts2DBFWcRYsCaarxxvuMWGLfAGmuBeZ\/xggXXed+y4wKOW2DcAut0C4zBdZ3u\/nHlxy0wboFhtcAYXIfVsuN0xy0wboFWWmChJjIG14Xac+Nyj1tg3ALzugXG4Dqvu2dcuHELzL0FXNJwtM6DJr1Sc6nB8SjE3ivsfPFzbNBRPudc2yqTdxg8nen2p4sUzmBL2wa6SyLOgPueicbgOlMLjf3HLbAAWsAtMNeZ3fQqyU0tN8+8wuZHAcuqAA0P6QCMIBdIUHwzhRG2jNuGXdrK6twtOv\/885Oz2U31cNHEhRSA59xrkIsw6u4yTbgxY4FwycVZ3frtyfo34FQn59idO3crUbrOZrt44yEmeTk\/Llw\/NAbXflppHGbcAvO8Bf7v\/\/6veiTc2w+uQTsn7XKF22beh3C12O1CgOaRF1wsjtbFDbfkEABzSw2xc0PCCDusJnA1Oy4p4Ao32GCD6gF5dQjyWIsbkADPzb4gwO9Ksttq4cZ0acZbGDhwAPuwhz2set+EXTqee+SGM3V70PVr9fOQDdMbItrSjUfnq721IS1n0v1yhHaUlrDdaAyu3Vpm7D5ugQXUAitWrEge7wGmbpl5NcyLbJ6yJOYCFLf+gKVbTF41i+rhzFxXduXXew1EbQ+nA2y\/eQa4HNCP8G2bwArIRboeN3K9GfcZ5EaiyyYem8FNUgUgwOwKrRtcvpHbgDjR8mKK35STpssG2sHbFtzceNRmkXeAtQXG9XWLkPcYPHUI9L1brA2RW4gRr8kcg2tTq4zdxi2wwFrAgzAe3sFteaoRt4ojO+igg6qfovZ6GgACRN7bdaU4qgiwvK2Am\/MmBRHdg0AeBnL1leiOU4vwTO8SlO7eMfDmL7Gav2\/poDIcv5Sm\/\/WmAo4wXNXB1XHxEAD1PgV\/QOd35YAbosLAubpy7RvNBHrS6UZUCkCXPwkg51y93qdMbtp568DjNRYe6gPhutEYXLu1zNh93AJrsAXoFut6wW7fgMyTj8RW4j+wIU7j0gAkYKAz5Q8wXBHlF9XzipSHWbz25o4+7i+AGLB516EEY\/Fcb5YP8dkrYoDZK2rEewCL+wW20hJefZj9UM65+l0x6SFlpy5QfouIB4s8O9iNgJ+FRjzifs454UC9spVzTg94wAOqH5LkhqtXJn7bb7998uCNhcS1Zc9a4nbperWv+kqT6kA7x8t44jfRoibHsdu4BcYtsGZbgBjvAe9+CLDh8OgZcVN0jZ6KJFL7FQmcoXRwtJ4YLEEBJwtQqQRwZn4dAfeHEwQm3tHwrkMJxlrGC2bi0t8SlekkpVGK4tQJdKQeJ\/Iwj3hNBLyAFj+vzIUpXyoO6g2LhXqpI53qTERHjIA7XbMy4nLZbZoR+7lFPfkR\/emace3y8hqY9rzwwgsToNUG4pAK1JMuVlm70Rhcu7XM2H3cAmuwBbydgfvrh+gXgQWA9bYrLoxJFYCTJJp7qhFwencX56pq3lLNOSfcnRMFQJfKoCThgB+zJPpP7ykDdqDEDxgy6WdXPeiTAKz8cdf8msg7zREeqNGBAlOcpF8esCCUz3MqP70q7hn3CsBxyYDQjr5yyccjPBYKwKgdcOHsXj\/DpXMrOXTqAC+Z0e9qKyoSD\/dTUXjzVn44dZJAnZOXX53G4FpvkfH3uAUWYAsAIyIskMHpMX17j5bYD6CAFi4sqheg6aF0etfddtstAUpiMVDzQDUOkSgecUoT2OBY6XaJ78Aq\/HGqFgabZdzYqQvY64RrxBFyB\/g4aJyxXyaxI68OOEWnHzzLCACJ6ThxC4nNOyCP2y\/D0OMCWqoQXCcunB3HKQ9ufl1Bvvy8WAeMcfoeY7fZJYyfx1EPZdK2NsNw1OL1ojG49mqdsd+4BRZICwAEAIADtNtO\/HUiAPcFIOkrifk777xzpW9ULTv0wMNTi97IJdZz9wYskRgQ4YZtdnGvE7ChGgBw4gJAYbxri1tlOmOK0xQOYPEPwrHiAL0NDEB9KyegwwVbEIAZuzgAkS5U2XDEVAjs\/IKEsWh4WFv9wr0fU1yATQ8LqHHHyk21ssEGGyRnX50goBaYmJiYMckxuM7YROMA4xZorwVszDiQTky24+6xaBtVdsCdqZxtTi4LEGFxjDZq6EKd4+TuN828LQsAcaM4Mtwi8MHZAV2cI4DG3eJi\/QSPd3P9igVu1iZQvWyhGgBAAYDCAFScMxEdyG655ZaJSC48\/yAcsTrjNpUNt2xBAHJ27XHUwtoM87NBVBseZ6fusEhcddVVSZ2FQUR28ehl+RPtuXcjiwLVg0XEgiScI20WE9ypdgH29LZUBdoLd2tBchzMr2roT\/GaaAyuTa0ydhu3wBBaALdDH0mfSs9J\/2nn+\/rrr0\/AzAT26wAm8aDZ2yGnBiAy47gAqt+\/omMk1h5xxBFJvgGCABF44hYnJycrPz8uqUx+G00coOP31vzaRgBdvVzAHBepXqWfvKgCggBu6Q\/YXDEllvsZGr\/OcfzxxydlwsXK+4QTTkhOKnBzu4w+1qIgrl\/JoFfmB5xx7NQIuHTnZnG06lbmWbdTQWh3bSFP\/rhT6gvl8vtd8sFB8\/OLEtpCPzmKpd8sBPyaaAyuTa0ydhu3QMstgPPyUz5EZCKrXWr6Q7efcK02pXBduE6gQu85SBFwhdLCIeJSxXWNFNi4NIDbwpniwojrfouKKsDRIz8NhKO1u44jA5Q4a8CKu8T9Krc02yKiv515C4G0gZTFQdv4bTYgiqunx9VWzq5aQITH+aurOimPuNpOHYC5hcWJAMBL7QCgcesA3skFG13aWxhcrnrjWKWl7b3D4Hzvueeem4C+M7ba0a8sywu3DIS7\/VCidNAYXLXCmMYtMOQWwEmZuDg6INeUHYA0qYGb3eymMIO4AYIAoIjX5CYM9whTmtxxcVNuLVqkLe8ySd\/cu7kBzNJvJrv0cOuhD+4nfD1\/39KZKW7df2TgSmdDD2RlrheC3oICue6+EL9Dmb755pvPWHyrrBWXOWPgEQfQJ0191XYx5OE8Jp1f22nPh\/QcEzryyCMrcRdXWZbJ2U46P20Q7jaibJrgGOn7wr00jTF6SGmX7l6G4m48sZd+Y\/voW2Ak4ApUseQvfelLExHFxC2rijV33gybTWld+s3FLh87f3NJo1tcZ+XspJakDhMTE4kYRZSpx91qq60ScS9IWOIGM9yYwkXcmEhAuIlMpAgbpoUs7E0mnZK2BmjqoX\/o+eiUKPMtDPRW9H9lWSItOi8U3\/2aRGObN0QycYhlp5xySlIOZwm7gYmwC5GIuIDVFVSi9x577DGt\/\/kfe+yxiZir35HNo7333juZE3SMTfV2+8hmERHfa1cRxkUBgGvs0ZvigsNvbI6+BVoHVxOHotpqbJcQINCBUArTqViZnY2Lqlq96XYczLVD5wEJceihpBPhBjUBayik6Wt8D5pGr\/BEO3Vyxs4ZP0p1O6+U6hTlztiZLAhYSUs5nKMLolfizgw3pnDcEY7ehAHCTeShCeGCTDYASSelbcO9yXSURT9pexsCwM3ihmuSrn6iWyrj6lOPeRBd99lnn9Krp11ZnKN0PlH7COyhEQ+LePGIHsxONfe1gSyYdJrESbpDbalfgZ4+RkDQ9VRMh29EL2tBteHlaJXddmT33aIoXf3jwL9D7\/rA5pNF3gKlP\/WRnW4L5uzbsjmm8SyvskxNIctwwiK63jIsvW7Ui7v6+Ra2JOH418lpC1R3H\/RbuSI\/fRXztZ5OWSflVN4I05RGq+AKCKzGr371q6vdTwMBcDpuQbFsUJiUDvFGoYiEDgCb6DiYABDHQaz60oywg5j0JM7E2Qncd999k5dwTPAyDSJZt4YswzXZbUZYDACDw9S4Ref+1NXAxq2YLMigjzQAMK4DQNlx9PoQ7tNrRI6jWFzswEZ47UYhj0tpImcUIyyTfoleylEUOr76BMOJbrrppkkZ3Sc3EZXRQXPcqH7AYeKOtJcd5LKNrrvuumQDQlhHUXDp8i1Jv9cXMxsl0pGvXV6D2U4sINEOxgUgKtNZqHZzAKdq0cKp2xTRT+ru3CaQ1eeA1m6+sWoMuW1kDP3mN79JFm+bTtwQxsRiTuzXTtLC2dLTOifqEgE9rXG0Zd4AABAASURBVLSYdLzlPGurLeWvHMawBVn\/A516+o5FKaMFQl0R6TXCAUWnDOKbaQxwE1b65oqNL3XnXxJgM7a1W+k+qF3ZMTfA0vxyKmLZsmWNyXSre7c0WgVXV\/BMOpOFAvnss89OwEcjOOpgghkwUXIdA\/gMBoCiUZGVWBjAYtCwz4aIvhoKZ+nIhVU+0gEcVhvHUMKtXxOHB5gsCiaQRYGbXUWDSplxI+5sq5vJEWnrvOXLlyciG67FPWZAs9122yXp4TpjpQY8yofjIy7WCWev\/XArkf6KFSsS0JP34sWLE0ki\/ACexcyuKi7RbqjzfY694CZNBmEBAI7SmT47urhy7sjExl0pZ845EXXd0OGHAKtBSqz1jTxkTPS1GOEMtAfSNjnnhMsXbqGT\/tJ3xrn2dbRIfdXrpJNOqt4o1cYhUekHfWJB8xiIcBYvwIjT1T4OsCOLHwI05pgzrBZGbU9Hiwkx\/6TH9K0MFjRlQOzyKAnI4UT5G4fmROlf2oEIjhrgmd+ATVkswGU4dgs40\/xnliRPZS\/d6nZzVV701BaQuj\/VCcbJYsRPmmU9ZqqLOEjZ1cGxKvkAdPmqK\/8g39yb6t4tjVbBlRKdmKzhrZpWX5WnCsCJRkGBAbHfpDNZHRkBNhrcAABWJpw7zuLgCg1aXEAvsjLizMQJuvjii9NRRx2V+NEphjvuTH7EeDpH\/r3SLv0AWgxeHQycTAidZPKYKOrIBOwGYeSLU3nd615XHaoWl54WGAFDkwloOzYivDx6qQQAJw5TGOGDcJYAlj7VBA93XLFBguOxKDjTiMs1sa699tpkMQOqyqxfDGzcv4keaYQJLPQJHTrOibsFi6grfcBuojsXaBGVHk4NF0dlgVNQBvk76yn+QicH4EkudteNedyrSR7kZg8gRcCHjlQb+DbuLUCOBZnE3LUlqQJpZ+nrIwyKPBB1inaThn7DuTJ9u1XEbwZKxq1FGWMDDPVNlDlMYwQDYHyb19IU1hg2h3yXxE3YkFKAX\/i7mGAsGKfhVprawiIN6Bx7Kv3Y+Sszf4DIDXFTj+B6caTGu7yjHqVpIVFOdVAXaaibcmOSfAf55s6fm\/DiiY\/YufETRthWwRVISTzO2bG7y3zTTTclK61VlpubEw4F42Qo9IEyLowYi1MCpia1FVt4gI2rMxh7EWDFQYpTEv2UFT\/c6HQ1PPEG4BrI4vZKu\/TDceIATQZgqWFx3sAMh25QmyS41LIt5A9MPAJhBdQBMYG0iYlBNWBxEtZEOvDAA5NBXyfckUmkDs4CCl+SDsa5S5M7URXIsQM9pvz1jX4QDgFX7W9xoI4wWAE0N3FK+uQnP5kib8AKNPWxOlg0tIkHQdSZ+kNaEZ\/6RxzccbdJFmEXignotDPGwXjDnVtYjQ+Apa1JNVRGxp8NQ0Cj3YV1BhMBT3EAUPQ7d0BiPODabNQiC6ux062NjCWLMGJvCmcsYoL4laJ55M0Un0QqzEwE\/MxX4AfoqAYwMhZjcY1d+bA3EebKgm4cNZUZZ25u1eNGPcQx1oAtrtI4VIc6YajqabT53Rq42gCxWWEiGQRRSIPLgMLNEGu5AzsT3SDDWRKNrS5ATqd4KzFUA8ITS+k4cXi9CBgAJHGaCGAQyeiBiUzLly9PK1asSMpr8NYbv9u3TjFQrIIGDWIHqDgMnbzjjjsmkyZuiQC0nHPKOSfAjLPBmZekXaQVZcftmZDxXZpAS5vi+nqBk3xxjwZ0zrl6rR7XidtWDisydYa+szgKT0WQc076g5hKHwx0y\/xLu8XRwmIB0lfaQLlx+zho+WvniAOAtA9QxxGF+9pgGv\/63XjAHAAY9SIZGBdUB05IuMJJF29M4jItNsR+cQCoPgCc2hABN+lYzIAvqQKxk3j4tUF0mRYC5S9JP2Eq+skDuCkvYgfcUfd+4huHwtk\/YNbJmMUY1N27fcOWsi5hx7l2i9OGe2vg6lYDToSoGWJiFDAAxvGecAMcBqFvpolsYvvGfQJKG06++eNkgWAv0hnSFack6RKfcXJPeMITko7GFfRaPcv4TXaTALeBQ0TsOBdA53k0k0NbmDDiGxBWW5OP0h4Q06USW5ANKG5Ed+0oThOpC8ASV750n03huFHFeIbNIqYN2V2J5Gdx8ao60LSBgksAAOy4JqAPWKkpXKlsmsCAApd24oknJvXT7xZKbSAPZHG18cGO6NJwEuwAxq0b9rWJbFgR5REOFRCQUJzEMM61L1AElPpFHxgr2oC+G4dIzWQsA19SHlUBf9\/SBMaIHYcmXdye8cH0LXxJ\/djNCeOzzlgASoussut3aVFtqBt9pe82KLheUpn2aUrTOFWOJr8mN+OtXh\/fmCRlVwd1EVfdpC0P30G+ufPnJrx44iN2bvyEEbYVcHXUinLeYLCJJYOSTDDiKx1iAGb449SIR8QHIhLQEx4oERkj3KAmgDLw6PjobdytNuiANO6X26BpluHFtyGkzNxNHCsubsPmGTc\/SRHcOvDBreoIEw03AsgMImoCnQEscYC4PvHrFGCJaxVGW+EMIpyJZ5EDiPrBqQ35GhjLli1LwDTCMunFLQQA0QC0QCiDiZlzTurGLmyQwU\/qUH7gqEz8SBrauARS7kHK5naSjT5qHrvnFrvwX5tMbWnyIiKxvtVXFh2AoS8szvpFvfmTuAAtUKUaszNNsqBesOkoXJCFkdoFsXPHMBjbvpm+uesvXCdi5zZbwtjgxIG5tOga5YMz9S0PZMwzEXeiuTjm9Ux5h8gv3XJsl\/Es9PBEmtIPP9\/mH7eJiYmKiVK28G8y+ctLXcSThjqqK84Wl8v0zZ2\/cMKLJz5i58ZPGGFbAVfcCG5T4zW9c2jgABETjNivknScNm5MeJsAVAfAwMqpMsFhCTsb0kl22gG\/fA1sKgHiMfts0ow49I84RuIdfZeVyqJBV0Sfa\/cW5ydfmxp+jpcf8c\/GlTJpL0BrwVmyZEkCODhF4jlwxoFEfkDbmVBcovC4PaI2lUqEYVo9LVJ0wVQG0qMCcN7SM3LCBOGE6LhtUghDFNQ22o3KgO7Umdm6zhiHbSOSCgAYiEetQBVgcY30w7R4UqEAe+oYgG0xlWeEWZtMfWThCcIFkmJMeost9RmgxdXqF4uXvqcKYFKx6BdH9aQhnvhlGxkbuFbEzk+7WiiBK9Bmcm+bLAzStGhYPLxNAHi4BRnX5gdmRjhj0jjBKUaYuZhAF5iRBI3XSIsbpkqe8m4qW4QNU9mFUxfxuEcd2UsKd+GEF098xM6NnzjCtgKuxCD6IxsfEq6TSWjH3vEc4MnfpDXhcDommoFmVefXBgFQgxTRI+EmbMC0kTaOz7EPuhwAhHvDMRrcdI4a1nEli4dBr9NzzgnYASCcCfEf+GoDkw3HArAAMf2vNouyUnfoNKuo\/ICgdgv\/MHGzBrB8AaB6e3GoTEtY6guLAA4+CPdqc1EeNumIOCY3jlycIJMGOFoInZrAjWrr8K+b6swt55wsOB7eWFs5VvW00FoAgyyixoDJjgPVtoiIjdvnpl3sqhsnTgB4Sk8Y6TWR\/jRXcEzUTNQKZbgdO\/p+ICMNQESkR+xlOHbzwngDEL5nImlIC5BYOGI+hzs\/du78hUPGST1teQsjbPgph\/LwC7cmk9TInWTGDMLwyK+ebvg3mfIXXrwov3DmEjemb\/Xiz0148bgjdm78hBG2FXCVuM0YIiV7E5lkgKX0I1oTkZsAoAw3W7tNFBMZGM42jW7xcNxABhgBNQMeYFkkgkuUN32n+uHeDBi6NuoKHYHz4K5jiIAAmhTgSbN6vsIAVoOv7ld+U6XYqNO5pXtpV15ShrRK0l5Ak+4XN23C67cyrnqqF1VGvT\/LcGEXxsRygcSC02uMRJyFbLrSCxxmIuEsgqQ0Om39II6xYSwE2fwjZscENw6ME22KqSEN2E8woS2G0hDH+ML9LuS27FV27UD0dnKiV7g16dcauK7JSsyXvAEJ8CnLU3fjz60MU9oBXy\/\/Muxc7DbRqBroypvSIcoRcXFiTf5jt7m3gMWLSmUU\/T330s6\/FDArSMmYFhaLlO\/5QAsCXOmVJicnE91sU6NhxYm39FVN\/v24ARH6LQrpCM\/NxgJuMtzmYgI04lqkQWTEocg33EZpUrzjnHGhuB7cz+LFi5P64gjoyZWXGoKpbDhQZ5KpNHzPluiF5aNvI42mtIXRB\/oiws3WVLf6GDF2qGL4zTbdXvGij6lcSCR07xGebl47qps6GgfKZywrFzv3sIsnrP6g8lm8eDGniowt+u3qY\/xnXrTAggBXbwwAV7uOWs2EtOljQKGJzs6ggWnS+0Y2gQxc4fshceVDVI\/w9GbSJZaFW2kS7eheAWTp3mS3kWEX30F7dmVExECgws49QKwpjTbdbJJoR5w0lY7NFGoNlyrs6FMHAF7H50xkE1p4ulz62diYnE2Z9JcNOVdnbcJJI9KWd6nn1fb6QF8IV5KFkMrFrnkZpwxT2vWTY2PqoL2RslCBGFu+bbSWcQaxK6OyGBMWLHa3qixaxHSbnrjVeh8T60kKQBXQq6+xQAfPTnVGL+8Wo\/RsflEnIGNcHYwtxxeNJWqdQco9DjucFpj34AoknU21Q06XqBnsuhJZ7bgiAGWSGoS+kd1rA1H4fgh3YILLDxfniqqjU73iCi9flx6EM2nEZ\/ouiZ5Mem5w0bEpo40tu50mkm\/AO8yJASzpiJEbU8puA8WmmquZyptzrn7ADodERWEzxs4zDpKey007HBdw1E4l6RNp9CJtZjNPmnZYQySmngBObrcBCfpsR856pcVPeKcbLAa+gSNiL4nUg5xKAXLaGxk7OHig55ses4zXzW4zUzsiYAqYLVj6E+BZrLSVdsa98lNOGzCue9s9d3THqQ4AKh+nSZRRv9DVA1tlw0ioJ+5aPzlhIKzrlsphA1U7egjHcTi6eeNNmm2TeqqvequDhbcpjzKcsMZehBNHXO6oX7+IH6a6o\/ierWmRUg4Ux8ea0irrpPzqEeGa\/OY9uAIbg41+EJelMnbkyxtbbqo4K4hTMCCRCeoImPAzEXBzUFv6dnUdh8KxGcz1uAAA92NjyqRQNmENELu\/Tj7Y2cdNRFx24OGIio0wuiETwOkFh8ZtLjlj6mckAFjEa9M0ECwgdqKdEzQ5TXZgYHKqBzB1VIy7dxFsjJj8MZmFBY4556Qd6gSQZyqzdtC+znlaMCO8SxEAKeectDuQIULLO8KEaRHV58AZ2CCctfa3iYP0h7KKw8QZAjlHBXHo1BL6wuUJh\/bFdRLC62ni9CKTkQiun6XrzCXxPeJoP+NRus4yG1duo9nZB4J29y1a6qZMwoubc0782LkVlG688cak3zAMNiulg0t1aiDnXN2mo78FwgDHyRXptE3qqb7q7cSKM8+ApZ6PcNzMRUBk7BmDpA2LK5WTNLRhP37SKklaxom5U7oPald2C6wyKqvjXeZDUzrq1FR3aTjm6bKUOqkpDc8qAAAQAElEQVSbOs5rcDUpiEYGlYKrsAlsEFmZiYzImU1+uALfyGSlShDeZLAqMYUrSR4aAldJJyZtjeOqnw4EOmV4EwQIODaDTCIDHsDqIKSDuImHi3WCQHq4NeW28wtwTXBHcXBaOthCIk4vMnFwDjg7dZKfcvaKww9oE039PlHOOZm4JqgjcbgqhKvGiQJ839rPAqBcFgZx3CTCoTrm4+qthSKImkRevci5Wv7Rn+zaApAqC7UMoOPuPLDztuwlaUflMy4CjHB6+kY99R+1BQlHPGK067Y55wq8AC9QcDTQmAFy6kA9YLyJI0y3ttV\/AIEJ6IwDY9CCIG6Qo1LaSbtZtI0LnKiyA1WLk7x9BxmP4qsXYBaXiRvWL5gKY8C45GaxoBoxvowl0p3xZrIbe8AMN4bYpV2StIwn\/sZT0xyJ8EBEPdVXvQGb+lCpRJgwu20wiUdNgthx3+KQ+HxzR+ylnzAl2RMw97Qx93o9ZqqLOEjZ1cH4thnmBII6qiv\/IN\/cm+ouDf3hyKRyKz+a1+BqcgA9opyJo6IGJI7RJAzCeaoc8Ag3pnDCi9eNTEoTm7\/LASa\/gapzDHjp8gtSDro78Rwr4m8CESuBjgY2yCO8M7A4tfjWQcAUh2ECAQj1M3EizEymwYAzsdIaYAaaOABBuevEnb\/JaGMFp+db2QO81BWYUVlYPHLOSZmUUX6AAbfLDRDFxMUFIqu6hUy6vQj3a\/U3CIUTBxgAG+XDjWyzzTYJp4fL1hfCleQomDq7IcbdGKHaoJMk2uMYuSNp6gOqDN\/ADPDGuFAf7a8f1FWYQcjCpszqRMVSxiUJWKwtSEBS+zGFsUCoo\/xxscYM8i0MkNUnwjL1iXJTaeh3bjnn6rU3Z4fVS1sah9pMv7KLPxPpX8fwLBgAzaJSH0PA19wwZox7aQpr\/FFv+G4ioIfxoKe38NXD6EdpArd+\/SwSygwIAWLE46YeuEd+GBagqAz1+vi2kCi7OqiLdNRNeSy6voN8c+fPTXjxxEfsmDTpWqzkO6\/BVSXqpDFNFrosoqCBYDWh0NegDrS70OAMoXDC4zAMHGaZngFs8mkwIo7GWbp0acXdOINL9DcJAKIJVMa1+WUA45JwCTaF+AMJZuhhcX42N0wk7iWZTG7T4BjVofTrZdeROhcgmNQGlQHn7KN61om79HCqODb6SUCi\/iYy8q2uwgjLzYFsAOGWWYCrHWztCqxMdosY6mchk26dqB+4OZ+Lu9NH2pV6gohu0hnUQEW4IGI59YByGMz01cRvC6SFC0gRpdUHJ2zQR9zS1O7aXz9og\/DTZhbrJkCIMCaQ9lQ+6gVlDT9ASwVig86CknNO+lsbq5sx4fy1uIATWCL1yXnlAz\/sAJnJzytYFjKmfPi5jABQ1NcYNH4RlYu0tQEuCsWCJm5J2iA4QPVV7\/oYEr9ctMr4vew4WCocix4wK8Na9PVjmX\/49\/LTnsZjhA0z0lFPbWJe4CqVoV4f38ZaxJ2rKS9jALCbkxaTBQGuALCsPF0TTgkHacUu\/di91UqkJQ767kYmIz0n3aK0zjvvvGQQ4zS8bUAvaNACEWK4dAESMdYmm7wBncaMPAx8wBRuwMkOvEkVYcI0+A1k4ITrCPeZTHkCg3o4AxKI1Il7hFUe9QM6wEQbmPRM9THRc145uS0U3mZw5ZVoKryNQpPXQLawGaTMSL8fUz4AUFiLobbXn27xKZ98PFXJz8017YS71Qcmoz7ApVr0pEGaYCJcmzrgBsMd12XC8a+Tdtf++kG56v7dvi1mJpBJZVG3mAub80rVg\/YkIeDa6K2NCWNL2S3U1EbAygJJ324zChCqu8Ve\/zD1jT0G35dffnlyM8k45W5MkWBseAFgCx8Qc7JAeJtz0QbK1g\/hxPVnfQxpQ23bTxr1MIDbeCFhhh+g1ea+gS8miB318uMfXCR7P9SLc+0nfj9hzElSq3GmrhiFeQ2uCorjMwGQShJHcZgGl0HmCI4BZKDyR\/ROBpfbKxGPey8ySXQaMDWATY4IjyMx8QAJbsWOLK7BxIgwYSqfQS+OvAFU+NVNHWIgm1wmUt1\/0G\/cljLWiXs9LaK0OqiX8jodgaPVjtoWGFgoDHzXZYErt6Y619Pu9Q3YLZYWrHo46hMcide17KiHvz7RPoAVJ0JqAPjEeW0Y4ZjiA1fjxrcde2Y3kq721w\/aoVu4urtND+BuIpGijFVhtCkApXZg15YB9IBTGwoXm63CEF+djAgQVg4LCnDOOSfcuH4Sj06cbhpQ55wTMAR6uG8cGpOaitQl\/KDUi3MF7trbuJauK9LKaaz77kbmlXDaWhhltqCxa\/eSg+zlJzzCWCgHez+kXepzwrd8lV3Z1EVa6iZtefgO8s2dPzfhxRMfcQuKes5rcFVYHWqSO4fqm0iqgkRBg08lrezEc\/7ICoLztHrYyLASWomZ\/OsEEKkV6ELtvgKUMgzuSacTyYh0Jrv8cVlluLCbCDhnu9HOcoZ7aRLrpasONlGAGuARRjl7lVeYQalM02Q0yU186Ziorr0CPcDAzeICFExSIjswBg4RRxhu0gUyvvshaRmkwLEM76iXSWBRxOnLP\/yBDbFfm\/KjcjGAbeZEmLoJqJ0eodKo+\/mWPjFOu2t\/\/aA\/YvHA7Zv4+l34ktQZ0KuHEwsl16X9lJfYz\/QN8LSj9jRJpfXIRz6SUZFwwFmZon0jbM652nyUVxW488deBFC2gFiEqKXMCWWxmFBFWRA7QRMOG9eJ2LnNltQTl44RkRZdo8UFZ+pbHsiGMhNxt1klT\/PSN+YIMJFMyoW\/l5\/4QfqIZBjlCHff1FPSIV1G2cK\/yVR24dRFPGmoo7rq55iHvrnzF0548cRH+of+mB\/GAR7Ne3DFnRKXcKFA0GaGVY9+ycA3GXE6OgzHEg3ouJTdX0+2hVuTCbQ984cj8lSbSdUUjg4NmJrUDnqL0xROBxj4lP9M5auHA2IGAe6mJGWhw6uHb+PbKm0wU4HY1QaoOedk8bIQGRw4J4PHJLdZZGBpc+3In3tZFqBgIpEe9IENqNK\/yW6HmT6QiOgUgrZwbM4btcqEM6u\/9iUdwI5TZXfUihpBf\/guycQjyRj8gMYEUKcyDLsJT2Qv21946gZuwnQjZecHIGwaaSeLrY0+YIrLB\/wWWWNA+1hkN9hgg2RBEhdT4MSE8hm3JqW40pQ\/XbTy5JyrH5PkTvQXRtmloT+NS\/NAHbWfPC1cQIuUJbywbRGOXVpxhAqgAx5uQTg5x9owN8IR\/0kHuGKbx9yFtUBpO2Te9fITPshCpN1IKfSv4c7NeJWnPJrKFmHDVHbhcLLicY86spcU7sIJL574iJ26h59ykWYWlZFHaacfspNqxW3K18qDU8HhWQGJRrhLmxg2Cmxw5JwTFQCOgw7UAAvuT0MjaQMWjcH0XRKuFwDS8ZngTRO2DM8ujDjyshGGC+SOHOey4gFgmwA2xriXBJSANLCok4VEOU2cMk7YcXcmsQ41yOSB2CNMN1Ncx49wUupAF+UyAEAyecVTNuBl8cBlEsGJdUCPrlu+wiGAa1HjLh1pcp+JpC+sXW6Ars42d5xk0NczxQfyQEW5gTowjTjagdqGXthNLOWKcRBhmDifetv7tjiqF3ACCgBB+JK0o\/FUkj7BrVgE1A3nKR1cNoAjLfBTdmlZ0LxpKz\/fyoMAM8lIfAufb+lIw\/gO8JcOIFVHgCItTIfJzV0\/W6xx58YH0jbyKkldlL3s19K\/bpeGtNS9bJ9w58eu3fgLh4xpadXd+SHt3eT3uMc9Pb3kJWen2247ON1++y6S6Gw4b5be\/e5vp7PPvm9ab73dK7f4YxNWevKWXrj3MoUTXrwov\/DKzI3pW734cxNePO6InRu\/aM81Bq7A0MTE4SlcENB1wB7QmXxWNGIOu8HvqqBTAla56BAcgFf2iUdNYBZpN5nA0YaKF5sAZhnGgNNQ8indw+7MIVWBNMLNoMcBE4EivegUA1lHWTgsEvKtE3ABztITltkmmfjKbCJSWyhvzrn6ZVI7ncpGnI483SLT5iSGcJupXSJcN9PC4USHc7H0vFZ9R9vs8NbjaHt9IM+6n\/DGQlleYQC18NrdN9KWBr9FwgSh56y3vW\/5iS\/OoGRTSh7GtfyN8b322ivJy2YckMQIaHtqGOkb547A4WyNX3kDWZtR2sd5bVKb89E4JxuwxpE+pCrhh9RPXJdYfDtDbXNLHguVAOovf\/nxdPPNZ6VbbjmxMm+66bLE7ayzXpSWLXtIYnK78sr7zrtqjgxciS50WEQAZDIRCZ0N9Y34E\/eIzFhrKz2wNbFNCuIpcYl+DMfrm+hjUJtkgMAj204JELMAlXRRANa864GGAr3jHe9IJlCDVytOADaAv58ETdp+wg0SBuepHIPEWchhTz311GR8kgKMZxymsQ8kMRD0\/MAV92vhAc5RX+1U9he9v70B\/cIvwpWm8BbO0m0h2QErQL3jjs2mFds3Kh19H3XUTmliYln1e3hpnvwbGbgS44krZb2BJwo3oqlwRCBhQ0dF7PFNpyQsPZZ4xFFHhcS78847O+LCHYleanJyMlnhy40WXNnJJ58s+pjGLbBGWsA7v3TepCT6aUBrM82GLcaCvh0TQGW0Rgo4TzIFlrfe+rKBS4PDHTjSECOMDFzVgT7PoWp6CWIzt9gdZQ8CnMAS8Uc55wRUuaXiH31a6cZOz0WUlA8OQXDuVAfsYxq3wBBaoO8knZ\/GxVJDIKBKxKcu6TuRtTjg73\/\/4A6jNJ1j7be6oZftN\/www40MXF1pxGG6dUNMt+OZc65eYCoraLMFEJZuOedqx7R0Ywe6uFkEeJG4xCbqAjo5HKuwyKBmImWYC13xtrel72+7bZpLGsOMq47DolLlcv755ydt3ZSXDbOoI9G3DBPua6NZ1nM+2+l6R1W+QfLCuc62XOIOktds8+kn3qJ+ArURhn51pnRwrFQAwgFJZlD5zZ7zyuuEjrYEqEbYHXbYIdHdcg83pl1q5tpINkaChl0\/OkESA8nAbjcdeT1P4i21jF17N4b0Cb17GU78YVOI2Ew07Pykb8Eo6zlf7VRqa7JsgPD223eZdhLgttsOTrNRCUQ9Fi36fljXuDkycKUzrdc255XXLMMdGNqwynnlwWkgivjnvNIt55WmsPSrOeeOCHGHIBVxB+RUA3S3uFtpoADuKuD4z6xaANfqkDSgkoBzq765+w5yhM7ueHyzxwH6cBuF6eaTI3PUUOxt5DlOY+4tAETt+tOT2rhi2vVnB7qzyQGwrrfexbOJOpQ4IwNXonu9BjhVVLoDVwApPBNAMoUpTfH4Ac2cM+8pkBXOES9+0sl5pf\/aCq7Eb3fVg6rGGPIfB8UjCyc7ysPc3J37Uy6HqR1Ncva03AEXZlh0v6O+mEpa+o1HpHfdsf80t\/u84KxhZT9Od4YWAKxNIDpbUC2zwwmX32vSPhJwdWwq51xd43PgGzfp\/nPOK93qDuEMiAAAEABJREFUDQA4ASMSNr6F4xZm2HNuTifnlaAqPMDN+a5vbmsLXXnllamk+VAvOlag6uSG2zpOb9TVAnRjw6D1fnNjesRFS6fogBvfO2UPd1LPMPKW5nxo\/\/laBgA6F7G\/V72kjQP++c8f1SvYyPxGAq7u7KtRzjl5yAQ3SVfKDegxg5zbC9AMN2bOqwNozneBpXQQIA4q02GXr7TWJsIdBsca5ijq53pp5OPQu9tS8c20oLod5CC\/M5nC2MTkF+Sa6zDIDacj7\/2NFPSUmz81ZQ83YWbM++KL02zCRP3aNumx6XORo1vlYmUx446Ei7y7uYf\/qM25nATot6yXXHJsv0GHGm4k4OrAeL+1oBYQFhgym4hfzivBNudcqQO4CZtzro5spdq\/nHNyEqHmvGA\/Y\/Oq5FjDPmil6E09AOIa6kxxgaVNLPfXTWSXQRx8517GpZMFpn6twHE415dLVUIZdhj2627+fQr66W\/Xm7KH2zDyHGaaTmS4dWVzMDbNHOHiDmQtrDYPtfXExET1YEs395nKqV\/bJptn0vzSl96SrrrqW0Mnea1pGgm4duvMnHPKOa\/mnXOuVAgAE0UA9pxX+uFSuYdbac959SNe\/P1OFnMhU4BqW3XweAYVjRtwVDb9pKvNkbBuAeEC2U1mt49sbtlA8iBJziv71115m1zCjYJefNEvU9A7f3j\/KXu4jaIMTXlYcNzWYjb5uxbt5pZN2dKfvtqrS3TZ3LWvTUJ2aXmDgPTghSaXb1wP7+YuzkwEwMe0U5pLG4wEXN26ynnlJCs7NcT30o3oDjjDtGnlW5jSFDfn6WnGhBe2tPtG0mIuZMKhzET91o9+0IaT67busvfTPoCTSgBXYOB57cg3dxPfDSRcrIlNpBYGuRvPv9+yzTXc3Xd9fgr6+eI9p+zhNj390X05NUNl4t4\/aYHYjtPU9p5ddC7bq1jC9SqV9iUxAF3hHI3T7uzOk2+66aasqZt75dn5YwzUqeO8oP9bmHptXm+88cZT9RMO989B+yN2bqQt9jq5km8RLNOJMF7G8iAVcyTg6sEVYIdwOUwbVTmv5EKjYGECTmGQcPHNn1uYYc95ejqOYfELMBZeGjlPB2PuC4WCYw3Rv5fZb52An8nsWiaR0wUPg62f+KWI33RaQBqud9INAmK6YW4l1Sd1W99bX35c2vgxT52iRVvvOWUPd2Hayq+eTlnHJjtJwatjXsbSRh4A8jiRPtauHnXpJUXQqTr+5iGXpvQHcTMG6jRI\/EHC2nCymeWkANP3IPH7DWuB96ONHuhBzrd7PY90ZkFzUxNnLz2nijx56Z1oz2cGeUrS05zCWPj82gPARV4b23fffavLM74R5kI4j+14StNv0Y0EXBUQ5Zyru\/855+rnVFLnXwmAnc806IZWzrnSuUoHAdEQR9mliXJuF1h\/vdNO6ff3Hd1LPDNxq6W\/+vZLHvhw193DIbghr0IZJP3G7xYOd4aDmpycTHSBLhQAhTJ8fVK3+f2jt+2Rgl7\/kw+k59z9s1Pf3NvMq55WWcewu2hhcjONUwyAse5KOEYAp5rzyn0Bj2BHvLqJ0\/WeLNAITlUYzxGa4OzUBaGC6eYu3CjJ8SvnWG+99eXVpQGm72EcndLOZ555Ztp9992rh1w87KQdSFja1iJmk5Uay2Pq9nm8xOeiC\/K0qfce+BmzHie34PnlZI\/raHuSAVD2jYxzz3N6g9dbvvYcFo2igdve0FLmnPOUXjbnlXbuBm7Od31zQwawgczeFt1w7Gh2JQ2GXpxq3W829XO3HfdEhPdmaK80gO+SJUuqq7+ezyON0PeVcQyuEEmBK6A1uMswo7AffNtt6fHLlqW7f+ELsltj5AUrJybioRYT12agyX700UcnahMLHI7IG61NBQWs3OsvptG\/0rM6a+zRd\/pX4NHNXRqjJBwqbrUpT0en+Df5zcXNM5ZeyrOYmT9EeEyXMehZRsAqfRdMSG6k65K4lU+Jwo6TTz65AmwbiSSM+AbifiZJGE9K4lwtnCMBV5VoopzzwBta0sGR5pxZq\/iAs\/ro\/GHPOSfqhM7n1P+cmze5pgKMLcmbo95X9bZocEH1ZsEt5ZwryWOnDveuvfUH91T8M7G9Bm+1p38CyAZkEWTo1s3uuCOdeMstVT6HnX562uX22yv7mvgD7HA4foSRiuTss89ONgPpV0MkPf7445NwFi4bjWU5gYH29l4sNQs6f9W7DnTZFlh6XIudc8X6o5t7me4o7LfddlDPbGby7xm5wdOGIO6VyRtoAks\/6ePnd4LZ81M4nijFbQJFZ7EROzeivUfIpVEnkoZr4PoA0bPaqJQ+tY\/+GAm4DrqhlXOuJi8u1MZWziuB1HfOuTpqZVLnPJ1DDTeT3WQWPq36F36rPheMYSKWIn8\/9n4rNzExkQwIOkNxrLYmplfzTVJudQK62lIbm+BEUN\/cAUCcFjCxAbXHnqVhwNk4Yx8FAdZLttxyWlYf2nrrad+j\/KDjo\/fDxXsqE6dpsQGoFh\/tRPxUJr+Ooe3Yg7QnYAWwjls5DmdCx4ZWhCMhEFnjO8xu7uE\/THMmznQm\/0HLhhul7gKQ4hrXfhbKGLToM8PdS2TC+801L\/bhQNm5+SFIEoewuFIbiOzI98mrOFmcq18goaelVvOzPtXbJgIOm6wcJiAiQjJxljlPB8coB\/8gkzjs\/NnDDDsQZUf8cs4VR8teUs65\/FwQdivgoNRPxXBGrqTiLuNCh3g2oExser1uu6U4Lr9NZqLjwOzOEkkBgM0EXJO0AAggkCY1AbdR0UEddcCGNVWA7+BkR1WOyMdC5GFsagAbgNQDfpIEwGIgLHC+bbDY6AIOEbc0qQZsQpZuFjWLLuDW3hbNWOya3Mu4o7C7898rn5n8e8Vt8rOZBTTDz+JFGvDIPlWMsRp+QNCmYnyHyS04X5u8bvQ5ymlDjMqBeiE4VwwKCcRPReF6EcwbCecaBc45T9vQyjlXHGoq\/tHTAck6qOacq40rQfkD1JxXgqXJnnOuOFrxUOr8E65jVP9zzqn8rhzn8Oful16a0BySmDHqbLhWk2mmhA0Wynig6CgW8Sji2KUG5n7bCgCE+6CmjQBxenGrAGUY9JrNNksvv\/VW2a9GB3dA9\/CttkrDyDfSXC3TjoP20J+Aj2RgchI7ndDAVRJHcUvGNQakE2W1\/9LgaLFiBtmIpGel9x70nOsoVCXrr396FHU1E7De7W7DeWwl51wxWS4P0bPiQl2YCc5VYYAiMNT+fi7K4sfOLThf\/QVjSGnmB52r3\/HzMz6AlorAAgm02cXHWCySwbApdBz1fIBgHfAonQ0whWUGiZtzZlQNlnOeMoXlIa2ccwXYDq3nfBeg5rwyfGrx373f\/\/4WU7srKQp4BORmQ3el1GwzCPjgNFesWME6jfzon7Yk3kzzWPVB5YITwI1RHwADE3uVd2UQYXHHwoQduFSeq\/7Ud9nb+P7BZz+bjrz88lU5NBvHXnJJSitWzOpqaz9lbMrVIoOzvOiiixLdH\/ILuyY+ThY3ql9sojz5yU9uSiJJg9jZ5IkpCYkBWIdqoJu7NO71sY+ls26+eei6aAC60Ub7yXIacV9\/\/dPSei2\/ZGUR0oYkMpKAOWTMGu\/aiAk8uSmQNqJeYQJRagGnW\/ghJwhsRjrhIU1vZpBCkIUNRgmH9CF1DS55JOAqU2TCQv8SVEu7MCVQCl8S\/yBqBXb+Oa8E0bCrLLu0hQkCAmGfjyZARcMuG5HJC\/h0gE15eVTcr6YSd+r+BmfOuVrAduqxoYU7ACTCGMj6A9eQ2v5XpEfPeuKvflW4dLd242y7x5ibjzOT+tYRH5PUUSEbh1dccUVybIqb8Yp7oqrZesj6YW31gFe8oqoUgC25+cqx5T8AdJNNtk8bbnhcR3o9rTLvda\/9O+abWs5pZXI4VWP8sssuSxOdvQUnYJwcwAy46eY8KyA11mNc4v6pY3CnFjlqGqkZuzYa6VmNa25B\/LjBI\/7XXntt9RNTJIiRgGu5oWVVBX4556p8OeeKA60+Vv0xyHJe6S6sb5XIOa8KkSoRnxvSSDnnKh1hfTPFzTlXcXx\/\/etfr+zz8Q+ujkjfBs21fjYAKPOb0qHL0+baE1dqsfTNne4vNrQcFwouS3r6pCm9Nt3oWXf53e\/6SlK4Uepfv\/rVryY\/nGkD69xzz002DnGuFiuLnd1t+mq7zURNj970VZFVgZzj1Ac+9QnAZm9yB6z1RejJHf10cOXiDYNwqhtu+KZ0j3scUYGq72Hkg8M\/55xzknHHTowHtCWdcMIJVdbCGcc+tLtLANwcTQypzrsILiLYZ9BH9N78kZuNgJuOlb99DFyws+MjAVcZm4A5rwQ6FUE55woQ2YNMQmGDTGJ+gJIbO8o5VzpY7ohfzplXdQzLoIq4HHPO6aEPfSjrvCSiS1s07ArqIwMJV9prQyvK4RgMzsxqHm5tmwBjUG704I7+Vby2y9IrPbvWJALckXnhTKsNGBMZ1wRozzvvvOqYVq90Sj874HR8RNJ+zrk2LUKjXGxGoefVPq6y4lrZ0U4dSesZz3gG66xIWlRdERnQOgUS33VzJOBazzS+c86rgSu\/nPM0zjTnzLlyqyydPznnagMLqAJXlFb9I\/5zz3llvFXOCeCGfb6YOFbUBscaaQxaN5tbxFT6o0HjzhTe1UBcrDpa0cvwsQHUn7lLz02oB++6a\/ragDfmLnjwg5N4beRfplHWsbTbfcahBh122GFJmzv7Gm7OGuOwQh9Yxu9mp0O0MPdzznXHb36z52bfsIHv4M6CRg0x7Hy0n1+eoI6JdnMCxgH\/+A6TxEWKiA2scC9NoOpSwn777ZfoWql4qBjc1vINyMvw7CMB124bWgpQJyCZc65AN+e7zHq4nHPlJHxlKf7YBc85V2mEc87z6xKBzkEmRdsUde7XxDFR1Nvp7DeO3e4IS9lf39DiZ9ACFHfnAQC3kkIMbct8\/J13povvdrcyi6727y9alJ52yy1D2dTqlqnJa6Ojmz93m1smrI0Y301E3SIMlUL4c9upw5nZPCzbunT\/3OmnT12qiHh1E\/DV3dr6JiWEKkY+wwRYu\/lOAuAuPXvpVEa9Ho4aWvyFw\/lre2OWymBycnLaj6cCarrV7373u1UywNv+kLlTOTT8GQm4Rr64SYpfZgAu0d03Yhc25zyNS+VW+rELz51JTA03YMuN2MVNGMTN9U72Mc2+BUxo+kBvB0gFN+Cbu+8gg9SuqWMsOCo7uOE3LNPk7TftH3TAtd+wbYZzOgBniqhWTNjYfOFGZUDfHfNjrnnTD9IpfumMM9LHNtlkrsnNOr6+ObG22TioGqffzAHfkiVLko0qCw59N\/Ed91mmwY\/U4G1iWOESgc0ufQJMY4Gb6GyIAWvHtDBuLnBww5BwdySLX5k2+0jA1YaWzIIAnV1T38CQGWQghF24nKdzoNzCX4MAVitI6QbA7dzxF57JH+Ay1yQRj+AqTvoAABAASURBVFGI8MMwh10\/N1OoWPQV07c8AaoNLTuxlPwGX86ZV3LUiJK\/+uj9Z9a+TbrEbomNUsdYlmHHHXdMrksiaoGNN944uRbrGxExnRYwhst4s7HrD+PLEbBrX\/vatPiaa7omc01anJanybRbujAN419T3wyrDzygQh0AZHGmFvgLLrgg1c9tW9z233\/\/RGcNjz73uc8lCxzO31FOuGJ8H3rooQlnq12oFfyyCkxxMYbeHNbwq9NIwNVxCCAnc4Vilt85r5yAOecU4ibQRWVY3yjnXOlbU+efGy7Lli2rNgByzinnnKxUWHxhse3MnHOqr1yd6EP\/T\/QHpkzUtgqgKb1hVwqXSiy18jN9y9OgJIY53nL55ZcnKzxQNbn9yoHNGuGGQTijQTmhgzv6P\/GGUZ5uaZqMn\/rUpxJyvMfxHxt+voMcYWuDEaDPlf7drrsuTaxY0Vikb6ctEkDdPF2dDk2npBVpIrX9Tzt36xt+basHcJGuowLEY489NmkDor4bVBauiYmJqSqyYwb0hTCYNdxpzjk5deHsq7Rg2FSkjgWgUjf0uk03EnBV2U55Us6ZUVHOd9k5AFuE2ym\/uflGpd13kEO9oS8UxlmznHMFwNLjBtQDuNMI\/znGYUOHOSoC4iOsYtesDMwAXkfw4mB7RMD5tkUf+vzn062PfWwk3Zf5y6c8JYnXVhkinV6ZOx5k8UHGqQnsBIHvIOIs0bRXOv366YOLr78+ffU+92mMskX6dgKoi9M1aSKtSBem3VLb\/0LP2i3dmfy7xevmTrViofeTONqbTt9ihQAuCYq0gLt19Ao2ANVID06QHEI1YyMWmIY\/M+ecnM6gt8XhcqvTSMAVG417BHKrFaCm+\/rgBz9Y6VtzXgm+Oa80xdMIKOy4UgMUR+qEAFbeOUKNSo+lQcrwVi5x0U4d5f9caNsXvzhtdsUVc\/oZiLnk3yuuwaSO85mUv2160He+M9CG1uYXXTS0\/uvW9nR\/dNDo2c9+diKy0vX5DrIJGI+4dEtnUPdXPO5x6Vc77NAY7c6U09Vp8wRYAWxjoDk47rfRRj1jv2nDDXv6z8YT93n44YcngApoIw3vZhxzzDHJ0Tc7\/BYfNxLDn4m7hRuuiVMxcCsJ8MIWkoH+hG2+yzDsIwFXhZQZMLRC5JwrVh27jqze\/AGkhlAxFO7s\/MVnRkW+973vJSy9lcPDCq7OepnGgV\/p3HDDDRX3mnNO11xzTXV9UPwxjaYF6KuaDrYPM\/cj7nnPGZN3UmD\/e91rxnDDCEDkj0UFE0BdsnTp0mkgX6pa5lqGsg++\/apXzZictpkx0IABLl5vva6L3mnrr5\/QgEn2DG6z1QF\/Y++4445LuNcyAjWMyxre1bDRGngSYQAwjtSvRbgGqw3Dj+nEB5WAdJiXXnpparpRNxJwpf+E9vSDABIHS9kclPNK7pSfwqus8BoFsPpm0q+Km3OuuFu6VTdRcs4p5yxqRaEfAb4xmJ\/1rGdVfuM\/o2kBmwREMKJTebB92LkDh344JeGGXZam9G2qxJlW1zGprV7wghekcGO6VUTaa4o\/iFu9D35x73unw2rPMNbTGwYXKY\/9OotZ\/ZicPjjiHvfg3SrZxMOxUo+Ven6MXGCMDDF6vqljtBU35NHy5z73ucki5ww47hbjh4SHR8LNRCMBV2Bng8Nv17h9Qp+k0kHunqs4PwW2Inz84x9PXg0iyiNXV1X6qquuSt67BJx2+zRAcAJhGpzSccYPsY+pewt4Aau77+x8SA4WU6LuAQccUF33DP1rGvK\/UXNK\/VbHGcnYf+g3zlzCNfXBGT\/72Ui5yLL8pVQBWIclPXjlzbwnrZb5x\/XW0o39nHPOSdqKPchYJfnG99FHH50QHa2fhMEZl+SWXYQNcyTgisPEflsdAJ\/jDI48BDm246wYPwVTCQWnSKZ8dgid\/gSYiuMKG32VoxDCD0LKgY1HzgAOEnemsI59nH\/++UnaH\/nIRxKxpB7H8RjctDDISYJ6mLl+y1f+6tpPWnRQu6\/6vaF+wvcbxgC34NUPtvcbfy7hmjilmzbZJA2DU+q3nMax8RtkQpO83v72t1dHgMJdvznr2m+6vcI19cH5HfVAffMP2A27beQRUgUO2Xevsi90v5GA63xpJODnV07puhDxgVtb5fPwrleNHD+S5j777MOYRnbMf9bhHoQBPE4STAswxw\/18Z4kXdEck1rw0Y8o9K+3P\/CBafkhh8yrOmEWnHTBdIyqYMaHOXDsFltMZfnjzobSsLjIqUxWWUgVQPy0jq51ldNQDarHZz7zmYkKZqaM+v3J7EjH\/MUs+WUJ+YR7mOsUuNL9ORLkhIFzbVQR3KIx5mIatADt+uuvT0QKt5bcXqqn6ZgHHY4wdb+5fuNYATzxRx690jMY7Kj2CjO43\/yK8QcPe1i69A1vqAr1w+c9L+Fcq4819McEp1N13VIRqLR8e09gYmIiWfCdmyS16R9h2ibj3Rz4yo03TulfL33Sk9IouchRAau2s9s\/OTmZvIzlDDa3IG287bbbJnMX7brrrskPRLIHmVPCUQeQuKkqnU6ShvntTQlvxx566KGcptE6Ba5qXr8HD+y4t0FONxDzIi27jDonvtm36HAMOufSzg4j9YCVL\/znagJsnLDFY6a0qGJcB\/b0nUlvAIljIyVOd\/heyKQ99nnLW9LbHv3o9PN9913jVXEW24LmyiRQ9UqbnyBx2sVxnld1xHVShzHZ9lGssvIxB7680Ubpmy9\/efrp3nuX3muNHaBSN2rT5cuXJ5va3KKC2vjVr3518iOazr1a7EiWNrF8I8AMoL0L8ZnPfCZRRVLjUP+ZN8AZNT0svygyGpvDbwGTXQcSJ9AZZ5xRrahWyeHnPj0HR9fslm7UmWB2VW02Gkh+DdM5y+mhF\/bXpzsqgflUA20PZIGqEzEmt4lrJ9oC7UTMqMp7w557jiqrkeWjbQEj8HO7im4bsS9ZsiQ5nuW4lgLdfvvtyfVtew6Al+QZ39z8YKEwNt1xrvoLuHqT1yZ7eeNOeiWtc+DqWJjjQdEIGjPsczWJW1a+SIdoDlDju24Gl+vH0Op+o\/g2UBwDIuoYkO66G0hW+RnyH3u32AJPfOITq2fsvCvg7QEcbovJr5bUoHPg9tt3SfOd7rhjs6l64jzpT0kDuM7zO5vMiD3nnKhljPupCIVF25sHwiOPD7nx5VysU05OwDjnqp8iGs6ViiC+mW984xvTOgWuHmvGGQAzNyucw+SmMeZKTja4S0+kC\/HfNcYyXe4eNglVgBseRDT63zLcMO3Ef0Ba5uEoiqNyOCYqAZO99B\/bh9sC1APOvyIPuVAX9VqU51Ia433QOXDzzWel+U63dxaAaBenjXCoNu5wnzaZETv9KN2rU0jCYyZsMLMj3yXnitt1McmpC6K\/PQ0crIdettlmmwqogbW4dVqnwBUAehxDYyF2bvVGme23jvBjZn7eGNcaR8usYsiEsUNs1aRzpRqg8+Q+2zwHjUfPRN\/nZlvENVgo5q3OyrXPPvtUP0kS\/mNz7i3geJUxR8fqgDopJ1KlE4xjWMwYN+Hfpmm8G\/fKgti59crDz7HMd6qXHwga58iihdgR1ZzwGAkqmkF\/Mtt5ZeqA8zscsWOmSHp1WqfAVeUNXKCG2Lm1RQap1VHaNpYiXase8k3349ynMEzf3NukKEdT\/ZyQsOFFfeF2kM01GywU9fStFgF2A5Beqs1yram0erXHqMr04Q9\/OJ166qnJ1Uq6dhxS5E1SAKquXIbbME3jwvhD7DPltckm26dN5jmtv\/5p06phs9aiha655pp0TYfYUby94V0H+w44eTe66FzNBZtgTtxQEdCLUyOyi0va9fYAN4yUxRJNy3zVxzoHrqvqvc4agBPQ+yE1r\/687GUvS27K2TWlg0W4aQPIW5frbEO1XHG3fbS3yayNqWAiC\/o7F2O0u4sGVDfhNzYHbwEcKbG9W0xqQQsZcKSW8\/tuGA1njum9EZUdnW2kAUzpX+lbudmrob7x+DniVqcxuNZbZAF\/40INin4mJyW8K8ZEmsnJyerhkKj6Jz7xiUTsoWMKt7E5vBaws00143eccJOOyQ0vt7U\/5e222y5RvQBDBDgRexA1mAXOfgcpwmZV2TL8uHnjhD9pD+dKZ22h9AIfKdDmoOOVN954Yxk9YWAWTXNZCz\/oN20ieSkL+NSr6Lk3v2Cqset+c\/m2adQPyA2ax8TERHLonO6oJGK8g8yOVRlIZbrKAnQd+Qqi2Kd3tZnl968OOeSQ6qEKYXFXXgzy\/myZztjeTguYiI72mLS4LD81oi+8wuQ1fGIpzqqd3FJaU3OgrfIPms6KFSuS6\/JULd3I9XDjGy7YB7HJRSX21re+NaFXvvKVySKHyeBP0qNeshHm6Bx9NdUB3a65t8beFhi0cWYT3iAFkEzxDVbcAGW1RqDrcjyDX5DHcoVzJAqgAB6N7Pdz5gKMykCXZaVbvHhxZNeKaWfTvXP6IkBIJEFETuKOFZb+qMzMNV8DAocURMzxTJoVlqhDl+SQ9VZbbVVFlQfxtfoY\/2mlBYCps6x2rqlh6AER7igyMIHpAI2hcOvXFKeNOdBvfgspnHmIa2V2K7eNXNTkDw\/22GOPpI35O4nQxKzxC1prOFec2bJly5IHXTQEHVasNq6u4eYc1I6KC8NdYwGlAJ3DDjssvfCFL0x+QjfCDmoCJUpzO\/MnnHBC9ZPQ9TQcuam79fMdr9ZTtHtFDBje8573TPRDABNna8cf2c20YEiXiGPVtZLTu9pIs\/nmTCDA9si44yujvOeuXOsS4YC0P25IvXFPvnFZuC1u+mzp0qXJ4uZ7EGprDgyS53wM66ijdjTfSXc2Zi1mxjfTnG8qN0YL1f1gBSbEpQTHrvyIoQ1r4OqSgU2wehzfaw24up6mQsAHF2q3EGdnV\/zAAw+sDmkDPWE0FjDVOERsIIP22muv5ElDz8IBJ2FnS8SNN7\/5zdXP8wLrUn+ps+3M46wHTZ9OLhYQXDkO1oCgjKcncoXSsR+AqQw4ochDOd73vvelhz\/84YkKwT12t1WczbUQnXnmmckExdEboNop4o7NubeAm29ESClpX6BK9+07yCYilYwz0eHWr9nWHOg3v\/kcznEp+lFSnU1bZSXCM12aMQfZvUpnriOndxA7svjpB\/0GKyyO5qwnBz2Lat55T8S+hbTqtNaAK9HXzl+cGbWT51A\/MIqGVHl2g9cOLTABTh5s4EcPaYDqFNwdN+F1ih3EXoQDqXOj3pXUsVY3agnpASw3RXDLRHFiSK90Sz95EGuI8VQZOpaIaTFQf7\/EgJOlYMfJEjnlGYSLpq7w6K9V3cUBbUGN4KgQfZ\/nBy04NgRctIi4Y3PuLWBs6TMp4X4OOuigpE+cNaXjM1aBLp2sN4uFG4SMgTbmwCB5ztew5oJ54nyrSxokPVwr09xjx3zhQLU7ghmIHVkI4QkmhU7VUS1A6pKc9ERAAAAGCElEQVQB1aHNLOBN+jOv622xVoCrVQXoELc0hkoCDD\/BoIE9CcYNEZs1rgaykeXaGvCjxD7ggAOq39xxDlFYRAwgDvDrRYC56dFpnDSSFgKsOs7tLY9\/A7A999wz9UNWVeoGemHld1zKCm1DxAUAV\/NwQtttt11VDx0vT\/UF5OzuQ9PxaQdhxbXAeJZNHegEncfEHVu9xRnTcFrAYkZaMt4s8KQZl0+YpK9Bcm1zDgyS73wNq\/0wEVRnNvTMNfOF6RvDBBdK5sXCh0o3zA+1G2AlDVIbIvMJE2Pe7rzzzsm8LtvC5thaAa4Aik4VYJUVxJ1ZyQFouDs5YEVi4uwouT\/60Y8mYRYvXlz9pnwAtDjEaioDgNiLpFnGE7ckKxudJ10uvabG5++qnvT7IYAnDvCj1sAp62g3w\/zag5+rAKRE+8suu6wCWOERQMXZEDupTHC8NljcUDEI\/UibVZx6AefquIl4YxpeCxgTNkkAKy6KBEJvTt0zaK5tzoF63receEvqRfXw5XeveOFXhm+yR7huZlMcY9ucAKA4S\/pWIMn0jbnAOOFskRMawFc830GkDSozlwgwbM4hn3TSScn88AaHOW2\/wiakPizLsuDBlXIax0WUAqZl5RyOB6AayM546Vfacbe+rXa4QiKx77ZIB3t1yiqHG6QXDf3voHlQdeCyHduxcOB66IT8FI76OxDt\/B2VRKQNhHW+tsKt4pboXYlIBonw9K6AOeKMzeG3gMWa7tvCNjk5mQ7qqAlIX3Sx1FH9lkC\/tjkH6vnedvBtqRfVw5ffveKFXxm+yR7huplNcYAhsLQPQUIg2ZEKbBxecMEFiUoMU0LVZt\/BHMDV+sb8OHWDcQGcdKziSAvoYsjMQ8flHH3Uj+Yjqa8sy4IHVzoqwKDyoSctK6ihgAvlc+nOjmMAekx6L6w\/nYuNHv5zIYpwk8SuPLUD0Zvuxq5jvRMGyccCcMUVVyQ3RMSzUYYb9ssG9EA4H88I4lL5I6KOPD2VZlOL+sAPPhoQHvU2EK3CBp7wYxpeC+gnCywxnl7cwk6aMDZIJE51AAJcbL+laHsO1PPd8LgNUy+qhy+\/e8ULvzJ8kz3CdTOb4hjTOEmASb8tjLlDnMe9mifcEObHfKBC8E115vYWKc63uQNYpYc5cfnG4gdoxXPUU9rClrSgwRVH6l42oHG7paxY2AGRAStsuDkLaDAfe+yxSYM5TGwHkf4SF4jjjbCzMZ1OOOWUU6pjYcRuD7kAPnnOJr0yjonkmAmgtGh4Wd4mlnbgZ5GhysB9A3Ig73yvuhkAVlvikom9dOnSZGGhpLcwaYsyr7G93RagdsHl1IkkQZqxsJMeSDiO8fWTu3Gt79ucA\/V8N3xTB1x7UD18+T1TXP5l+Ca7ML2oKQ5ANKf9sgBpwCkg4ajDbAbbP5lYdSEHc5JzTo5yup2oL8wtxzmp2MRD0jTvzGlzRdvfdtttyetYvoUpaUGDK8DACeA4u4nZuDQNCWii4sDHZo+73NQAbimFXxumnXd6HZ2DK6Gj0TFtpK3cuG3ipEWCrtaA0OGOldAJ2fGnf7XKOlblqp462\/GkTzWY3Mqih0X0zS4ZOGpiwLVRznEa01vAIudoD661TnTg+k1fmaQnnnhi9VNB01No\/pqvc6C5tKNxpTc15s05G7aYGhIbjAC09KROyQBcjAWGxOa3\/jF3+Lu5SaUY4EptQI0mntMHgJsqhpSBw3X8kQ49aghvFjS4qghuTCOyN1GTPzfcapugV88bmPXa4KqH7\/fbyQPiY3nInEhP9DGIpKM9DBALBxHGRhi1B7AHnhYb1\/es0F5Ux\/UQeyj8gTZOSjpjarcF6L39ThYOlTSDSEkkCPpzfco+qHrGeNbn3Urb5M9t2HOgW3mG7Y5JML7lA1C1sbFPn0pC01bqz07vag8DUSGYt8ibA04UvOc975FMIvoDXHMJUGNepGMu0pXT20qzCrzqz4IH11X1WDeMFmtp0NEtO7UAhHGz9MN0gIAZh+v0RItZrvNJ5ZyT15pwpxYyhNuxZ0BHSIIwUenz1vnGWgsa4P8BAAD\/\/+2dUiwAAAAGSURBVAMAE9prv6kHP4gAAAAASUVORK5CYII=","height":283,"width":792}}
%---
%[output:447f9930]
%   data: {"dataType":"image","outputData":{"dataUri":"data:image\/png;base64,iVBORw0KGgoAAAANSUhEUgAAAVcAAABWCAYAAAB7GtUJAAAQAElEQVR4AezdC6BVRbkH8G8QFd+oFJRUxzLw3sq45TWz8lJ609S8ZFpmmti7tKI0M63Eyp5WXLUytcQse5k91LTSJLMuvalMhcwwzUeZHktTFNl3\/eacOSw258A+wDlnAxv2d2atWTOzZr755j\/ffPNYoyZOnNj41Kc+1bjmmmsal156aWPXXXdtPP7xj298+ctfblx33XWNr3zlK40nPelJjW222abxyEc+svGFL3yh8bvf\/a5x+umnZ3f+\/PmN\/uiiiy7KccRD73rXuxrXX39948wzz8zpfe9732v89re\/bRx\/\/PE5zVmzZuX3Covk4wc\/+EG\/aV977bWNE088cZn0xWmV6mWWh1NPPbXxy1\/+svHFL36xcfHFFzfmzp3b+NrXvpbzV\/w8f8ELXtDYfvvtG29\/+9v7wl1wwQW5XFdddVXjuOOOy+l85CMfafzoRz\/KPMWrX\/3qVw15LoTXs2fPzmng509+8pOchncIj5+\/\/\/3vG1dffXWOx\/\/73\/9+wzvkT55dc+VVvayo7AceeGDO1wc\/+ME+nr3+9a\/P9ad8J598cgN95jOfyTLwv\/\/7v\/me33vf+97GN7\/5zZw\/+ScTyLU8ckt+v\/vd7zbU+y9+8YvGr3\/961x3yqMe1b3wrrnuL7vssoZ8uJcO2fBOdO6552b+fPSjH+3LCxk69thjc9rkEo\/JoXjK8Y1vfCPzzLvl+ZJLLsnl\/tznPtc4\/\/zzG\/L3ile8oqE+5LmQd+Pxi1\/84saVV16Zy6Ac+Cst6Z922mmNefPm5fTkD5199tmZh5dffnlDGZC6lSdt6qtf\/WpDnqSjvD\/\/+c9z2r+ueMPPO9WJeHhKpr1XHp7+9Kc3Pv7xj+c2iIdHHHFEX95KXWs7yjJ9+vS+ei3PWnHV809\/+tMGvpIj8ovvhS\/FlSfpyZ+8qLM999wzyyO+ePaOd7wjt5tXvepVfXnBN2XUblyXuMLXSXqeSb9cCy+Md68sDWHklSsOgllXXHFFbscrax\/CI5hzzjnnNF74whdmufxBhT\/KQ2bIEFwUrtAnP\/nJXD\/yp07VsTYkDX6jPvvZz8Zzn\/vcuOGGG+KEE06IBQsWRHd3dxxzzDFx5ZVXRpXJqALHjBkz4uUvf3k89alPDf+qwsTRRx8d73\/\/++Puu+\/mFQ899FBUoJzDVkKT\/cqfxzzmMbFkyZL44x\/\/GLfddlvMmTMnRo8eHf\/+7\/8eb3vb26JqxPm9wnd1dUVV4VExJSrwimc+85mZXvnKV8bf\/va3+Mc\/\/hEV8Ai6SvSvf\/0rp1810EgpRSXIMWrUqFz2W2+9NRqNRjz2sY\/NaeMHv3xT\/akYG\/vss0888YlPjK233jqe8pSn5DTGjx8fT3va06oQy\/5uv\/32XIZ777037rrrrqgaXyxatCh+85vfxKMe9agc+AMf+EDmW9VIA91zzz2xwQYbxLhx43Lam266aYwdOza8W5wNN9wwttxyyxxms802y3nICQ3wZ8qUKflJVeHZrf9Rvo997GOBlLPqeOKvf\/1r5i8eVyAef\/\/73+Phhx\/OhDfic++8885cp+oV\/9RXV1V3m2yySVRCFpVAxk033RQVCMaDDz6YqWpEOb2jjjoqDjnkEEllSilFBRQ5H\/KCR49+9KODnMkH+vGPfxyzZ8+OCrxj0qRJmT\/Pfvaz4xGPeERstdVWuc7wBX+qTjAe97jHxcYbbxzbbbddVA0j37\/2ta8NPKsaXlTAHWRB2f7whz\/EwoULwz\/vVb\/SUZb\/+q\/\/iv\/+7\/\/OaW2++eZRdVax7bbbxuLFi0MY+RI\/pZTvn\/Oc5+R3TJgwIeeJnOOXvKSUMn+1FTIuD9qafOy88865baj3\/\/zP\/wxygK\/awLe+9a0gQ\/L2jGc8QzazDOH9f\/zHf+T7wfx505veFM961rOyDHHx5CUveUnstNNOuT1r11VnEPfdd1+WzXrar3nNa6ICliDzz3\/+8+P\/\/u\/\/QtvUHqrOL77+9a+HesFDbZU8qVtp9NdGit8dd9wR3kmuxN1+++3j8MMPz7yvOgHRlyPlIAvND2AMrIE72mjz8\/7utQVye8ABB8Rf\/vKXXM\/qaerUqRnnuru7+6LxU0cVoOZw6sdDvPy3f\/s3lzGKYCoMjy996UuZUZhF+PbYY49coQRDo9t9991jo402yhG9lJDLvMZPQFU0sNSIvTQHrP4QfIJOgIBL5RVVr5DBRnjp8kME85RTToknPOEJUWl0WaBf\/epXZyCuesAMMFWvH1VPIXjsuOOOUfWeoZNYEX3oQx+KCZWw50i9fwgI\/0rDyCChsWtIQAyYaQzFrzdK\/OlPf4p3vvOduRFU2kbIi3JXWlKcdNJJUWkqAUBKeO\/UGDVKDVJ+yzOuCgImL3vZy2LatGmhgQFhaSJhuBq5hqau8L6E4Qc8hBuIgB4hl\/eBwhR\/9Vv11FGNJDJ9+MMfzp3BLbfckoE+pZRBhaABAcAhP\/IobwCHkAIxnbHO4EUvelGWmzFjxgT+yg8h1DDe+ta3BmASr+ShuBp8NUrI+ZCfStPKHf0OO+yQgVo4cicfOkN5TynlfAJnvHnggQey7OjkNHLyLp44BYjdq0su0jA1Lh3C\/fffn0GYrCij54hCgvgJr72oE20Fr6Qn\/wCSX0op5IUfBUFetQlp4Q\/58FxH773yrwHr8KrRSgA+HZd6VA7xlOmf\/\/xn7qTf8573rLQNlPYhLJlJKYX4+ASIdBTasnqSPzxSz5Vm7XV9pL3oFAAvMJwxY0Z8+9vfznXy+c9\/PitK6gV\/dQjkTierXOShL6HeC36eCSOsOOKSk94gce6552YlCHh7P3+dzP777587GXH41UkdKouy1v37uybHb3nLWwLGVCOSALBveMMbQh1UI9EM8mRaXPk97LDDcoeOX11dXVkJVa+UAZ2McKNk7qyzzsralR6SoNBEIbH7argVBx10UMycOTP4AV4RkZcA4BtvvDEIoQoCijQ7zwsRGEKt8VVDsOytAdLeCNsuu+yS\/RRwypQpWUsjUDQePeARRxyRtSC9JOGq1P8c3h\/ADbCA9IpITwigxKlTZQrJGiu\/apiae2rXelGdAaEhQPyQ8unVAbC4\/ArhHaGohkhZq+KvkfAHHgRI\/glxNfQI+QEsNAGCgO+f+MQnYosttsgAIT5KKWUNS0PGI36FUkqhgsv96rryKA9ltECIvJPA0KZTShmsdD4ppb7XpZSyFhTVP7wDKMpK6xW\/8s4dtWfK4V6nqGHiKZ7wq5MGY3RExuQppRSAVYeFz0CB\/GiE4nsP4q9xAw7yK686Yx1lZY4KGiow1jiFK\/kp7wZo6l4Z1BGAP\/LII\/PoRn0W3vzwhz\/M2jzFQxvBo5RSUDj23XffrMVK0zu4AEv+Cqjy08HocHRQ\/IGs9+vYgRv5UD4yIr57ACRuIXnEwxXJf\/2ZsJUJIGuE0pPu+973vqhMHRmo5Jem7v0333xz\/PnPfy6vygBKoSCv+EM5mDVrVsARgdS3dl3nqTbq2eoQDVZb9C48k5ZOiUtR4\/ZHZLaV9oE\/e+21V1DudBqVmSTI3Xe+8508+gC68IfcaJ\/eRabwiBxTTuGgTgdv8HSUQCrTsAsBSRVNjXfPXKDCCbrC1StWgQmUjEhHbw0gXvrSl2aA5IeeW5kdpKFS9OT8EFXf+wxrNBgAJKOV7SuYFWiDGp88aFQqSRqGYeIjWiIwE87wWsFozu7rxOxAUMSpk\/dijMaJsRor4dIDCYeRGrJGsdtuu0VX1UtpVGeccUZUdtnc82uIKgbYElxlpMUQsJRS1tpKg5cexutspK9XpR3KBzDAD0IrPMEorrK7NxQTr5B3KHO5H8hVPr14eV4ETg+tE6XVaOTeMX369DyUv\/DCC3NPLg6BwxeyQZsBnPxTSst0BPyQMhI8wCBN4Ss7aG686lkYRAbwz\/XkyZMDX+WFsMvzu9\/97qjszUGzr2xysffee+eOVt7k2xCUkEsT\/zRuGiAic5UNL7iAlXapg9dxq1MmLmVRLvXOVCHPRhjyray0KfUp\/8KpD6YveWQyk2\/PgLaOQxjtgBIivuc6LNdAUPqAkx8wBcoljDrWzip7bZ+Jyftpa8qgnRq2Cl8nGpO2WEB\/Za6wAEoe1TlTQ2WTDpqb95NBvCEvRqflXerDtWfainaPp4UoQzqyIlvCUkLwa+rUqW5Xi372s5\/lDtrojiavnDAJjwZKGN9baR9wRQeqI2VGoBDqbHSS6guWeKajoRhWtth44xvfGJXdO8iQdsiM6hm8Iv+jJKRx6xEQ2xTBOqka4rpHRQDqBXjyk5+cBX3hwoXZRpNSyj01YCM0ekaAxIaDNE7Mqaeh4ggGoMGw8owwl2uudFJKLgPAKVC+qf5omDoCjZTJIaWUK8C94RPBVAaNVuUTKAQgVRAgoe5jIOGvksxgwVThnvBp9JiFD+xkGiqNTjqGtwRfHgmWBqdxEippeqa3I5gaMIH1DoCjgRFEYd0LJ6\/4IUwhYKsC3Wvc0ipxCI9G51khmjwq90YU3kN7L37iu5aW9yF816kACPkB5OpOHQEtfsoprk5VfMTPM2lIjx9KKYXySk\/+1bGGKbzniF1NGGUUTkcHZLxT\/eEZoMRTcimPysHUUkhZvVdYoOlaXUjPqIO2SdaAMZfMeB+iQCibfIirHHiqE5QeLdS1evRM3pWfv\/r1LnJCC9ZRCmP0RaNTPmGFcw20DOU1QOFoQ+LLh3eRB6NI5VZGHQE5BH5Az\/BUp61h0+jf\/OY3Z3szvruvE+DxzoEIH\/CD5kohMiqltJB1dZVSynMP+FfSYBvVDqrJrKBMPO95z8vtUdmBLSWKKchIVBl0OnhJqaH1qWejuJJecflJF26oB7wWVxolDNdz4YQvedEWtRlx2F6ZD4RFeEhemtuHZ\/0RxdH7lYW5UKetM6OAkL8\/\/elPy0Wj9JEbHSottwQgc6OAkCGAykAqXmZk2j2iTZZIXMKgElS+QpmQIhyGBlRpNic9tGfSUfk0zGb1naAxExBOPYW0CxFittZqJj8UWC\/56U9\/Ok+8EYoSrhWXAIlTCAgTbtoQAS9pEDIVCng1aAwj8LQimpL301g0Er2l9ObNm5eFUBp6SL24xisOPhIuvZrnGjveecYmLW02Ku8UBglXqNynlAJY8C\/x9aCu5YVQ7LfffmGCzgSUCUjkmkaiAXuXjkkaiAYuH66RetBoES3MuxGNmrZIcIVTBv4ppT4zAMCP6h\/XuzQyjaDyyh0VXmsYtHoA6V7Hhggy8FEOciM+ecFn9YE0emWVXiE8o8nWG7+w+AKIDE2liTfKKV2NjZlJhyqviIYsjI6NzEpfPCQ\/7r1bB64uaSU6Y+VD6hqoKoPntGdxACL5xy9pkefi4gV\/ck\/pEB6RJ\/ZEPNJgPVdP6g7oikdTA2A6ll133TUrNOrGfZ10ZNKsk3akPvlRDMg0IHXvnToMcqk8KfUoM6Vd6vAAjDJTktjKybe8mYRVbvzkvpGuzAAAEABJREFUN2fOnMBT7U7HpD15hrQX+TDiQK7xVh505vKh7OLyEwYJB1D5CU95g02IVqnOYRetXBjlB3zkQV74rYx0FjoBwKrjkm\/yWQCWIlVPQ5vzPjLwhS98Ic9FlOdkYRTgJMiF2FHHjh0bhmPFj2uoXiKmlMIQD\/gdfPDBUQqnIQNqM4eGY7Q4mo\/eA4NK\/LqLIVCecBNGzwgvIdLQ9XaEgEoOiKQtjnCF5E0e5VneNRj3\/IVR4SaNCim4Bk7QCLlGKRxtTANTYYRIvj3XMNh35If9lxZIEGkoNC2ND+AQCn7S0\/NKg4bgXhgapDS9C5+FIQTippTy8MK7VS4\/4cRzrczyojHKP2EnrLQu5TLJxs\/78FPvDngILDMNAfAuwqMxarTeL33vKTzDN2GkjaTBwA+ghOXn\/RqV\/IgrT96pA\/Qe5RXGM3kXzzU+iiNNfNBATRp4Lt86tBLO6IT8iCNv\/OukroxKyFfxl6a6ljf1ix8AXMcvnLqiAGjAwujcpW10Qm7Ig3g6IbIIzJQ3pZQnGgE0fpJDYKosAFGdCSsuMMErYKNc3o033ifP5Eva4ss3WUop9U2oAr2Pf\/zjeSJXXGHIEV4h14BHfSsvXgIAeaiTdi1unV73utflCVfvQNorDVu+xCW7Oh9tzghGvWrHJsC8Q16lh69GvDRSYadNm5ZXTygvfkkLPwGg+mBuEQ6\/dIrSqJMOBR8pYrRQccQFihQGPJNX9SSc8PX4zddkhsyrL6a65uf93bOb07i1PR2OSTwKlM5G2wOweKPu8IEp0ioPda7NUACa0x0FJABboZR6KrrZ3\/CmHhmjZKLuV641MALmhXpToGf4VZ7XXcORQw89NACX3sczzGMDsVoA0Fo9ID3P+iN5k38CrrcHcu5VivC0iPqQSYOXf2q8jkEYgmEYQGgJJi1D5eolNQwNxHWpLO\/QGKUlb+JjvLxovFw9vZ5fWO+jEbhWIVwC590aUUopzz6yL2pEKaW8tE3a8lLASnhCo5ETZOnQYGgTOjqjA3kiEMoMvAyxaYPS0jkYRmv8enXpIWnKR8kTP6Txsc95llLKy6WAskauHMJ4Biw0Tq7Gih\/MMHgKNAGGnp4dHbgLp8GwrdMQ1bW08En+PXcvn9xmIis0JkBT542GRQYAszqjRbGlGV7LQ0mHZmv1gXdLS4OWZ7Jr6O1aXqTN5ecav\/HKc2l997vfzSsg8Fs4bUKaeA6c3AMjHY734J3GKQ3xU+rRENWle+Tac\/WO98CqEG0KPwGl9E4\/\/fRlNCbxByJat\/YGoGiQ8gxktQN+5EEZkVEaM4TRKZ7Ik\/xImwYJMMmR+lWH0vYMSJl8c41odvJumaf6AGDaFcUHuRZOmxMOicMPwQKgyh8Jx79OZfRd4lHAyK0JaqOwetiBrtVZAdaIyMvJrJqBYeLgFfMpnuMHedA5s8sOpDiO0uvQNldGhiVeonAKq9DuUSmcZ+7rJCO0krpf\/dpzBav7EUg9F3BQqPqz\/q7lTf5NMGmYNCj3ehvhDQeBfCGApyHonYG4StBYmDp0BADJPSEmUMBVunprtibPCKN3GEowhQA34EXL1qCVS+MSl1BJSzyCy2UbokURYvH06PJTBJwtm8Yo7plnnhlGCQBImtOnTw+rDVQ2INO7spHjG40YwEhH2fFPfPnAZ2UzKjC0JDjKBShpGjoneSGQ\/AEBPwJFg1BewyUmBI3cDL58qie9PP4TOFqzPNIsCZ+yaUhAD6CxYTHHkBd5oWVwyZQZV678M7Po\/NRbXebIhhUpGoOGbIIqpZ6VBIZuABDg6ygAOWDT6OUBSOC\/OQN5tsSKC+h1TurSxI58AB4TGoBZx0Cu8NNEhnLSGgs4zJw5M6\/BBtrMTfiLXzpjows8MiLQuSlTofPOOy8vdcPz4sf1fnUtrnpENCT2TZ02eVIvNCj+\/RH+AkBxEXnCMyMdcgCMmPSsFOAnb8pIRoUnx+YWaJPqR8fI38QNPqsDioBnVvCIR0alSRaFLQR8adoUHaMJyz4N9cvzNemSd3VN1tZkuvW0YA55waO6v2vyqe5HuVkXCKBYdUCbMgScOnVqX7EAgV6vkIbU97D3AhiarPqf\/\/mfvPSEMLBb0naABQDzTBhhe6PlZUmYacitN2MuMWsMHOoEpIEYAmCASxqAgyajcdDeaSKEVFyAKEx\/pNEBdmlZblSEWQfAT\/wST+dHk6JRA9\/iX1yNQ4NGtBD+QEjjNhEIDDWwerlpy7Qn2riVGLR44OEdgAG4ScdwEgAbRbjmJx15dN1MGrxhNyAGIECsOUx\/93ilnnV6daKVqReauzzQxFJK2RYsndLgdcCFZ0Y9RgY6YAAmHFLP8ofXAJpfIeUG6jqE4ldc\/p67Vx71UcizlFK2URY\/bn\/8IeM6DLZroEkZYNYYiIShNXtvK6RedKr1sPya86LDr4epX+MZ\/tT9XOMteWIHBcjaAf+hIu2jOd9D9a6B0l1lcNWDGkLrpYeiB2Jj1RvqIQfKfN2fdkHL0sgIIK0J0NTDtHLNjkIgCSzAo1lqbBqnZ\/U0gKI1r7QwwziCRTgtpQGUdaIdqWzAAaxpPXgHpAyBDUGAj9l06QLz+ruar+UJ372PwLpGwI6mxmZU4gAQgA2wNObiX1wAokGj8l7hAZEVEjqtEra4NH4gpiNRXtqp4RFtFu9oevjIVS80WRppib8iVz51kisK098zZhsaWJ3UofLjt46LnRA4FHDUEQAD4FrSBF4aPxt58evPNWoobUDn0l+YFfkBS5o10KHxlrD4Rp7UFc26tAHAXhSE4rJTMmkg18WfS3tSpyXdoXR1XPJMDgZ6DzlXZjKinQ4Ubjj9h\/JdfeBKQ7NdkTA2U\/PwQoao9yYIAAjNiXoMOAzTgIMwq0o0T8ZjvSbwMaQyVAPoA6VpmKwRaSiARVx+wkuDLbOQySn+\/ZEGZThoOAdQASKQ1zg9q8fRCNimAVIZHtaf1681IHkrfgBEAwBgVkQQTFqj4T9g0TCAr3BcdWCypMQXhqCKZ1itDpgaaFwEF+iVsMKl1GPD9az4r8iluVqWh4\/411wHXV1doUMDMExL7M06FzvUaKpsXpbskBOgxySxovfVn9HuaK0ppTwyqD9bnWtarGF4PQ0yA5gMtXWk2oAhJf4yEZS2gP80wXpcnXhpA4bntHUrK1ptA\/inkwT4VtOUtNnr1bX02Zz7438JK9\/eq4NcmQyWOKvryl9zGtqKjl5+m5+511Y8V1b36wNlcNUwaCJAiT2tToaTenLMqTNEI6JtaUBsL8CZoBK2gRqwYWMZrmvw\/YEw2x8gBRoEhhZkcoJ9kqFavJIPIFiIoRzQ6UEZ3Glw4tEopEUACwEsmonhifjACw8MfdnTNC7vU2b5kQdEE5ZGeT8NlLboPVzvOuKee8rjFbrMBIaZwJT9iZ1KekBNYwdIQIZA4oM6qJedkKob6WjYOhLhU0p511C9DjRiIAfcNeZSB96VUlounzQM4IK8W9mVEU\/UAZ4ZgusY8IPmvPXWW0fhp4ktvKDpe86sIM5giEanzJaTLZfBJg\/1V6\/Pt991V1OIFd\/iNzDDfxNkKaW8U482qS3gs7yQh3pKwpc2YFad\/Hve3AaYgIpGV9qAumR7JJvKqBMXF7EPkzvadX\/8F1c4BPTlHb8Gw9+Bwho9lbZQwngP8i4KAfu++0LsrMpFnshHf\/zXUStT4UOJuy67GVxV4OzZs\/sOzagPqzRyldzMBCDERqcyNGR2OzObQKIuKIaF5557bj5oQ1jMJ6QaoGGl4WJJG\/OtXWQXNFNJK0bWkBmmmhirpy3e+ZMnx+abXRobbfineMyjD48Nu2+Nza\/7QUw6c3J0XbBfbHjvrfGjzTeOZ0weH5PH75hp7CafixQPxiMWnxyTLpwcW\/\/hnBj10D9j\/N+Oj00f+GmM+fvvYqN7bszbHbfsPSDFu\/qjlFL8cNKkuPe662LRrbfGnhdf3F+wfv1ohQDPQyCaUsqTIiaB1IEhJx6bFW+uA3wQB8+OPfbYvJ8boOkk8dRz6eKlutKhmDBjGy51oAPSUAGnsEh6GpBra3bxH9HaARgNXIcKcKUtD93z58eGG\/8uNtvyonjspJ1icveTY9Ml10gitrznwpi0YHK8ZNK\/Mm0zabcotGTS\/oHKPXfTSc8LNO7+WTEqHshptPJnyYMPxh9PPjmumjw5Dqjy00qcEoa2lVIKI5A5c+ZESimfa2EkoR4GagM6VPVDrtnoAYcOp94G8FsnNbOa8AKAwuI\/sxe+p5TydueSF\/xnywZU1mPjPeqvDQhLLpT994+8Ir436dRMn5r0nUCfm3RhFCrPfjbpvVHo85O+GmjBpLdFoX9sfl08POqB+OZ2v4xTJ32vZGtAl4KUUopRFd15xRUxEP+NOmniVhfESPwbgXdmcB3sezViGpAJFTZHs+2WeFgPZ7hYT8\/sqp5VWPYfwxiz9WZrNUyalwrSWxseM9LTIOfMmZOT0YDNbAJXIJM9m\/5sM\/bMeOS4D8UGG\/y96cngbkcvviMee\/v0GP\/zk6sGFnlzgKGuPJrIomkCl+ZUx1YeG1S0Ssys4mkklqoYWhkRAMjKOwCvhu397us0YcKEfDoYEKWx09ZT6tG48FKalrGZOaW1Cie9eh3grTRpl\/ZEf\/Ob38wHcKgj5QYYngsHFDR49lzvU\/+Gh\/w23W67ePihrlj80HaCx1\/HvDUWbbBjvr5302fFvZstnVzMni382WzR92ODJXflOtAZrywK\/XuTKpC6qJxB\/WirlrAZVrN5p5TCTsMVJQIwdVjkurQBfKLFq0txKRvaA7ktbYCCgH9Ge5QS5g88pd2zqZrR91z8AkTSbW4D6pciklKKO3\/1q7ht7HWirJD+8+YD4+k3HNtHB9\/wokA73HByFNry\/skrTKP+UNmZTfgtuuWWuPuTn4z++C+v5Mckk+V5sZ78WyU80FjZnwgXAdFwDQsNDUwaaOj4Z\/jAIA80LE0x3LfryTCIdmQYxV5ouG02VWM1JKVplTQMu7yP5kT4pdtMYza+ttJer2r27rv\/r389FD9b8NdY8Nf5mbrvf2Xfs\/rF4g3Gxc0Tzombn39eLNlws\/yI8d2EjP3RtBiNJCVNOT\/Of8ZVf0dX1MxMAKjHRgUgrIs0jC1loc1YMmJChU2YhlIl1fcjmIDM8BFvygM84W9yBqkHWgz73OzZs4N90dIa9aJ+gIGVCerAMFhDFjalniVMrmmm0gCYSH2ytVpnTIMHuJY9TZs2LR\/6oSOQn5\/MmBETd3hWbP3ID8VtN50b3WOOiA0XL4hH\/vWkaMSGcfujTomD7hwdG8SyfBN3INp4yQ2xxUPfz6MHMiIcPuJRGa4WN6UUaaON4tEnnBA79Wqt5RnXRBstUxpIRw3kaPzSA4aWejmbwvIafKaReobIqnh1wk\/D53obGDNmTA5itOa9Jpjw2iqT0gbwU\/pGi7RcJgflo+EyLRhNlHoQVxoq9EEAABAASURBVILNbcDIwTJDdUZB+em73hVLqv\/CrohGLSGhaUVBep+lGNUYOByzB1OWToUMysM9r3tdbH7ttaEtRNM\/mrdyWcrFlGJis94GmoKvM7e4PejCAAKCBShodIavhjnsrhoyIJCoRu65Hhi5BrYmvgyJrA3VmIUlkCZhTIbo4TDfejq2xJRSAGCCDrCFHwz9bNON4s3bbRXbbfWqTFts\/LV+o49++M7Y9P65se1vTovtv7VPpJQCmGgk1nnS8KwJJPyG9CURAjW6utmgovpPgxaeJj5lypR85oFlQSUMDVEjBt60f2sQ8a885+p0rK0F6rR6jVIa9TpgcwUUpQ4Mc2m8OoYjjzwy+LsvdcBM01VNSAFQIC89dTN37ty8vZg9F1irI4DMXqaeUkrBXNNfHSy6\/0lx560fj8UP\/lts9eAF8bj7XhFju8+PR99xdIxa3B373DU69r0bl5SqNdr2gTNywGkVmLMT64wN3dlB6yRvS3772yjkvv6cZtqf9q+hWyJUJ5248FZ3FP96XcsQnukEgUpzG9ABk2P1CpTtNMNbvEdGP7Orzk9+AE5pAxQOzwvgWsWgzP21AZOd3vHDH\/4wy+h9f\/mLbK2Ufvq4r8Yvd\/hwRR\/J9OUdvhHohh1OiEJ3bfnzeGCj22KDxqgB06MgmUAlL2SPHI394x8zsGoL9Yg6aBODwuJZ\/dnQXLdPqpmDNCwNm4rfTGbWMa+e5V122SUfc2fiRzy9sd7ZTHU9HCE0DCWcyLVed+LEifk0KQwv4Ql1aRBMCbQA2oHe24TABRdckA+4JpglDnfmQxEzN+yhD2+1MB5dDXse0f2JOOWUo+OTJ7wofvikX8VB6b\/jsn9OiL+NvznTosedFU\/811Ni6wc\/HyRi67vPi0dfe2Scvvue8elnjotvH7wozj3xQMlnMpy23GhmZTfTaF772tfmszPzw+oPgdrkootik298Iwt75ZV\/VhgANnFoJXpwAJEfVn90IhqfZ9bU0gSa+U94lR+oGhUYHkpjRXVAwzQrTkMwKYPv+I9c0zxSSvkwZlqzoSkqdQCIgT3tjpYHbAG29cGAotSBTQNVMeIVV10bn9j0V3HRvkfFxS84IMY\/5j2RJt0Xt+83Pv75vD\/Gpk96TWwy8cQ4ZOsXx7yYEoUmxi2BRsfiKHRZ7B1o4a6Pi5ufsVU2CygHEwVgNdTGxzqllGLsQQf1UUop7\/grYQCayb6o\/pmVf8c73pEP87Y+t4ShvdIiqyDL\/XQua6oNmPwB\/uPGjVumDTAN2NQxZ86cAJomlwdqA9Ye28yhXCmlGNc4Mu5Mn+yjXWNuoB3ihihUrgrvucVvKfdHx4Xj\/xZffOxv48dbjIrbY8JyvCgeF1dzC2zLZefluOpBoeqy76fzIDdwollx6Au0jl6MWpVyEXaNXe+bUgpDVL2sbayGof2laVhkmYswhBjVw2n4gBdI77\/\/\/vmLB3pvgGvShXZneRZtqh6vfr1k8eLYpPuXsfF9N2TvJdVQ6a5Nbo+NN+i5z579\/Nlw0a2x6T0\/jYdShdT9PC9eGihw0siLH5ed6ZGf\/WyMP\/10t31EmAq4cd33Pey9ANzN6fU+6nNokeICGHzyoB3qAD\/kJaX7OHF3Nal3T6XB5Jv6n\/SviE1\/U\/dp+TqlFMB8ZUu51EGhFSWOfzoPHf+Kwq3sWTvwf2V5HM7nhffc+nvJN42VW\/dfH64zuGokesHSi9ddmhLtSo9fZwhgZQYAqkDPYRc0K1qVcIbEbF1sT+xZZpdpTDQgu1j03sIV0nMbismLYaoKEdbEl2fAWRpsPCVOu7hjNo8otKp5Uu5OHawq95byXz2sSiod\/q8K15bGwfdCS32H9KrtE8\/guqJc6nHYgvT4Jdxmm22Wjzoz6cQkUIgdsIShGTAbsDsZ5iCLqy3ZMmwt4YrL1kSDoxlaAmT4ZMbW8hbaMK3NEhXD8xKnbdwyHuIOQaY6ddACU\/G+UAvBBxOkw\/8WuFV4z20h+PoQZKXg2h8TLKg2adVVTYrQJgtZhmII318cfsIZ9lt65b5OnlmO4jlQtiCdCYEZgN2VSxOePn16PVp7XBOoQsOUo04dNDG68J\/b9Ggobjv8b+IqvhdqerS+3g4aXIGnZSMWOFsMXTchWAnAXFCYad2rCRp705HJMVqvZUnSAaAM+1YEiMNUQOOlJQtjNpafewvgxfFuYduKGJoKDUPGCh86dVBjduE\/t+Y9FJcd\/vfDVXwv1M\/j1fFaW+MOGlwPOeSQ\/AE2S0RKodlXrUE0q0qjLf5mn9lRaapmnc0+26dvcsf6QOta+Rv6i2N1gOUplnmZJBNGemy1lnQAXO8Sto8Ojph5Wo3eVF1XdMzeH4tCEyfcHGhsdEehuD0i04zK7aV3TTs50PT9zg1UPWntV3psbmsxVitUu9XBmLmLYubdFd8LbV1dVzTh6jui0Mzo+f\/suDoKbb74vkBjf3FPFHr14s8G6rr+pkDR6j+8L9RqnFUM1278vyF2iB0bL+2j69NXAlkRUOjQ+EKgafHNKDQu7gwkfqGyamNCWCugkURr\/wrvua3FWOdDDQpc9djWWtpxwnZauGMNqi2bNFnrVGmZnlkLZ2G2lQWA07If6wCB7Pjx4\/PXT60lBLhAli3W2kPAbWmShfD8abA0YutjbUaQdlsRgSo0xBnr1MEADC785w4QZE14d\/g\/ABfxvdAAQdY370GBq+VA1gNaJVBnFKC1jMriZuvvTACU5+I4bajRaASzAH\/bX63xtMAdIDMF2O0DmK3vMzHGBut0LMBsobblM7TjetrSagsqwyHuEGcIPzt10A+T8b5QP4\/XlFeH\/wNwsvCeO0CQlXqvYwEGBa6rUna7gQzlaai2Xlo1YB2rIT4t9qSTTsrJCsMUYHUBrdaRdZZdWSlg95blXjYf2PCQI7TTn22rzBSqLtvt16mDka2RDv9Hlv8j9fYhB1cFM6z3GQuuraN2otgSZ6mVfdbCsK\/SUmmxTAg0VBsNLKAXz4Ep1r9asiV8W1EZDnHbKmNLM4OHnTpYyo\/hvurwf7g5PvLvGxZwtULA\/nigyYZq66aDJ0xeFRb44Jl99FOmTMlbSO2lN+FlQsvWQ1sBnQ7k9KYSJ7tdEaccdXQfzdyrmkxB363cXvrLnhMDjb2hmjjppbCzD1nZVejeKkV0SeWiymnpB1QLtRRh+AMNaR3cWc0Njh0ft\/fSzB9VvEfPqdxe+sqXDw405oZFUej60ZMDxY4VPwpdU12jiysXVU5Lv8J\/bksRhjfQUPJ\/TDwQ98bmfXRn47RA49KbolDPdNah0TOt2PO3efLKJNbC6Aq0X1wcKFr9h++FVhpn\/QgwpOBq2ZShvuPVDPtpn7RWGqmJsa6urrA29qlPfWo4Zs+qAWSXFy3WJJYev+ytt4vGbq22qxp2pkJtlrlOHYxshXT4P7L8H8m3DxpczZZaWrWyTAtngmvjjTcOpww5lMR6VYeZ0D5tlQW2trVOmTIlaK1A1cQXG5UVBDRWcdhrabyA2WEbK3v3sD8vPTZ3GF6Ot506aGI03hdqerSmbzv874ejhffcfh6vj16DBlefnnYqj3NInVBkgspRgHVygpUDfw3lmQJopzNnzgxAauMAoLX5gP3V7Kttr07ZMWElHhMBmyxwpcHanWUCrG0riEAVGoZMduqgHyYX\/nP7ebwmvTr874eb+F5o6eP1+mrQ4OqMUFokkAR+Ngk4ws2xdBdeeGHQSmmkuDp79uxwLJl1r8ICYme\/upaGaxNXwloRQEu11pX2CohNclkdAKAB8YEHHhhldYE47UKLx1bWq14ajjx16mB5Lg9nHXT4P7L8X\/7t7ekzaHAFhieeeGIg9lBDJCeim4ByLGBXZUctRTXz7yAWwMjPYSxOxHJdyG4sW2Pt5gKuxb7KtuqEfethAa6VAkXDLXHbxV2674vhdehz1amD5Xk8nHXQ4f\/I8n\/5t7enz6DBVTGcrWniyTXgtDWVpmltqiMC+aOxY8eGIwsBLtB0ADN\/lFIKGqnVAGyutFTnDJhVZU6gCQNvxw5yCTQTgpO4ovZv7Cl3xzG3f6yPJl52c6CT9mhEoROvSIFevcNZUeiYKR8NNOb0+6NQmt6ITEdWbkW116zwsmcToY2E41YYbk0+bKc6mLLfr6MObgc\/+0uBTvpSVQe9dOLLqjqoaMYOn4hCZSPs3ptfGoW6pvwpUJpR1UFF0eK\/4a6DduL\/xLglrokn99H0mB2ou\/GJKDQ2vTWQQ7QL9awLWBg9G12tFZjQl8rlsWegaPHfcPO\/xWyNaLBBg6vJJme0OllczoGeyadCtsbytwGAmcD3f0xqAV8fJ\/M9JhqpbzKxvQJXXx5glxWPlsoswP4KVNlg+Vt14Ltdu+++u9u2olYFq\/COeeQlL3nJKpehpNOpg6UsHM466PB\/Kd\/L1XDyv7yz3d1Bg+vhhx+eP0OhYNap0kgdhs0E4IwBpgHPzPD7OuTee+8dvijgTFi7rxwnaNmV81nZXGnAVgE4HNuklvMEuE7UcvwgswKw9Y0ha2Xb8WyBVgTL5B++4IHTw2wFtjyN32CpUwfLc2w466DD\/5Hl\/\/Jvb0+fQYNrKQaNkzYJRC0LMvynrZbnXJNRzgOw+N9SK5\/fpvUCY6sNZs2aFWMr04Gw1sICXoDqXNepU6eG7bLMDL7vZBJM+FUFJO8YKqoPiQd6h47IgTWeW45m5xmeuF9V6tTBUs6NRB2sl\/xfyvJlrkaC\/8tkoA1vVglcTWIBC\/ZWmiVNlGbmQBd2VzZTw3vntB577LEhnPMCrHd13OAll1wSDmixpMtGAZNahv8A1ARWSil8NoYtlw2WPdZxhswCDoZpNz62ojU15xlPipbf\/KyV+04dLMul4a6DDv9Hlv\/Lvr097wYFrgTK1z+dWAXwzO6zpTq1yjpUS7DYXh2QTZs966yzwqddaJ4LFy4MX4J0Nuu+++4bwJmWKh4QxR7Df5NcKaUwuQVoLdmi5QFg6Tdrx93dW8fCCY\/ro2LYb5yRotAtjbMCTUyviUIHprcHemDxJlEoDq1yUVFjvypuRdVdS7+\/x7ZRqKUIVSBlsoytuhzUrx3rwMRHz3dcTa1MjNlhOmV6NHau+NhLzRMrJldefftnAx0Tp0Sh4+JDgR4aPTpQtPiv8J\/bYpRYlTpoR\/47o3h0LI5CD4QNsWOitAXu4sb7Ao1O745CO8b1ger8KnG7Q6pjo9V\/+F6o1Tirwv9W026HcIMCV7P1NE3Dc5+Dpn2Wtacmpyyu9tlpn5J2foCjBs8888ygyXZ1dQVQve666+LSSy8NYGlYbHLLtlaTV7Rd1zYOnH322WH9rCVZgFwaQNvmg3ZgXD0PrWhNlqDZCike7Z7myt7sfjDUqYP+uTVcdbD+8L9\/Pg\/kO1z8H+j97eg\/KHBVAMcEOl3ptttuC9dWA5i0stW1EPupg61N3NBeLauya8uZrHZbCc9EYKLLOQNMBSaJhgTCAAAQAElEQVS4hPvBD34QNFSTBia5rBqgzbLNHnfcceHAbfloJyq9PHegfJ122mn5EZuzc2ydX2sSMHsO8g++d+pgWabhfaFlnyy9W1N10OH\/Up6Wq8J7bvFrdtcU\/5vTbdf7QYPrYArCfEBbBZAvfelLA\/ga+s+ZMydopNJiZ7322mvDJgThHJ5NS7Vsiz3X0IFWS2Ow0YDWLF47USu9tvzqMKwWMKH31a9+ldeQU6cOlmXxcNdBh\/8jy\/9l3z68d0MKruyuhv6KZIbcLitaqBUENFFDY8AJQG0WALSAlQtsTYKJC5CBMbOAJV382olaBdeRyHOnDkaC60vfuRbwf2lmV+OqndvAahRrtaIOKbhagmXCClja4tpV2V3l1qSAmX8rBCzXMtwXhl3y7W9\/e3zkIx8Jy1x8hcBOGLZYh2QfffTRYa2rNProloiueTf10djL7gkUzmXtpbFhsNIde0f00WXVNYovVxe9dHjMDhTXR2SqnFZ+7SxYw1EHyr9rzI1CYxYvCnT9DpOj0JPDtMo1MfO2WEqPqq4rKs+4PVNit8ToxQ9naoX\/wtwZ46KQ+3ah4eC\/aan6hOKX4+BA+FmocGfXxl5RaG76bqCemukJWcKV02Fb5WPhPbfVOOt6uCEFV8upTFixoQJHdlZaqkktKwfYHa00YBZIKeVjB61vPeyww8JnXWixTAXAuKsCZodnH3PMMW1XJz3Q3QPh7Za5Th2MbI10+D+y\/B\/Jtw8ZuDIHmKD63Oc+F7Z62nlleRWNdNtttw3bXy3LesITnhCAd9asWeG0IZqsA1os+QK0rpkFrBygtdrZNJIM6+\/dD9w7Jgr193yk\/Dp1MFKc73lvu\/G\/J1dD87fIP3do3rD2pTpk4GqZ0Rvf+Ma8A8vSK0uoCBubK22UoR9Zy2q7q4keXydgHrCawMTWeeedF3aBAVcmAQdsWxvbdmy+s8pRoeqyXX6dOhjZmujwf2T5P9JvHzJwVTDnAzjxyrAfAVJAybbqHtmEAISBqM+9IBNdAJgWyyQgDvurXVq0XWm3FRVg5bZVxiI6dTCyFdLh\/8jyfyTfPqTgaumUXUh2VZntZyZgg7W+lT0VsLK\/Op\/g61\/\/esybNy9sIOAHiL\/97W+HQ7mdA2u9rDWxdoCNJMP6fXd35VuoumynX6cORrY2RoT\/I1HkIv\/ckXh\/G75zSMHVN7Hs6EIOarHcysy\/ob9ZVCdq0UoBqXNarYllj3VYC032kEMOiXPOOSesC2UWoL0ux8OLK59f1OjA6hqdXbm9dHocFWjXhyIKzTyvmqlGh1VuL82efUSgmFvFRZXT0o\/GWqilCMMXaDjqYFzcGUs3X46OmBeZdrx3fhS6IA4MdPmEPaLQ6xvjA52R7ohCz46eU167R28VqEqptV\/hP7e1GMMSajj4b5VGz\/oAawS+HF2xMNDO8YsoVOqnvjJgYeOcQF3piChUVmtMiNsDRav\/8L1Qq3HW8XCjhrJ8NFZLrpwPABif+MQnBk2WrdXEFvura0Dq2lrYF7zgBcH+6oxXp0jZ2YXYbdmwpDWUeV6ltItQcVcpgaGL1KmDoeNtKyl3+N8Kl9bNMGscXNlICRR2fepTnwoTWXZnObOV1gpAAavJqpe97GX5OZOAb2g9\/elPj6997WvhY4cAFzCb3ELPec5zglY70hNaykeztglCGTN1R7xq\/N2x+xgLa7PPiP6Rx3W1DpRtOf5X3O7jf3d1M8I\/eRwe\/o9wQeuvx\/dCdf\/1+Hq1wNVQ\/0tf+lI++QoPp0+fHg5wmTlzZkydOpVXJltXLclyY\/vhvHnzwtKsD37wg\/GsZz2Ld8yePTssvzr11FOD2YDt1b2zBEx82YfvrAHhcoQR+mPjwwknnBBO8mLakI3tFj0YL9zuH\/HMLf\/lto8cXKOjWBEJ0xdhFS7Wtzpo5r\/Om2mpj\/9\/X8pEvF0R7z0TZmmMwV+tb\/wfkEP4XmjAQOvXg9UCV0N0M\/smp7DN50sst3I4iXNY+SEgZGmVda42FFhB8JnPfCacEmVFgDDA01kCKaV8\/qsJMPdOz9ppp53CSgG2V5NiwrcD0U5s391+VGXMXRyRHoj8z6HfLmx9NDmns\/HVWhsmrOd1\/773vS8cUiOMsKtK63Md4L9DglJKEb38P\/ix3QFs8RNvO\/zHiWEgJrFCw\/C6teEVowabSRNPtEf7\/B0xaHgM9Mq9oT9bqQOxgafvPNE4ASRANUHFLMAGC5jsvLL8CgBbknXwwQfnxgGIpUlDpPkCcd\/iArbL5HlKxPtffUIfxZ7VU3R95fbSoi+MCZRGN6LQ9EPPCTTznIg+OqK6rigmVnFR5dR\/NjA46ctZtK973etijz32yI\/H3N+IUQ8viZfvfE8o0\/7775\/9\/Wk0GqFcNBzfCWNjZntenUO\/260OHogxYbKqUFR1kumGiOil62PHQDfEDpVXD5XplhmNraLQrHRPoDEh1d7eKnr+DcR\/Twv\/37XXHZFSBbY8K1pH+B8ragM41TMN+Ozg2oKKLo79opAwqDvGRqEpMS\/QkxsvjkLXpK8HEhZFq\/8KsHJbjbOOh1sOXNmLpk+fngEBcDaX31GDtq4aqi9cuDCDieMCy71hG\/CQjlOw2E19qBDIAiNAYxusobVDWKZOnRoAB7ja8mplAYAGog7ZpnlcdtllwaxAQwa2zXkarvsrr7wyfG3hjjvuCJNs11xzTTZhfOLwv8QOj3ooLv3pZvm+nh\/lccKXw2po9uzGe+21V9DKmT7qYcs13nXqoHBjqdsf\/+3006EV\/v\/4ms2XRqiuOvyvmDAcv+7qJYWqy84vYjlwpXVp2JZBHXTQQZlHFvQbYrkBriaqnGlpfaqvEXzlK1\/JZ7sa9rq3SUBPyx4LWJ773OfGBz7wgXDotfiWXmkoxx13XPgUjHDOevVONjTpsrsyH5jMsh7Wc8Pt4TqqT1mbqbu7O6xbVDZatAPDNeyTPzM+FizcOP5+x+jc2ShjiZtSiq6urgy61vcWf9p8uW52O3XQzJGe+\/747wlZKfxfXI0i1Al\/lFKH\/\/gw5ERjLTTkL1s7XjCqZNNsvS+r0soApB6fkJpQ8h0sp1WVsFynXAE+a1WBBm3LIRU0CZ92cRoWULasimZLY\/WBQscIbrPNNpJYIc2dOzfkBwgDWZ\/ktmJghZGG8aENDU7v8spb\/rBhtvnF\/e6WJcNSWjtQFt4XGnQmdQAuMTp1UDixcrfwn\/zl0Iurv\/j\/YOXWfmsb\/2tZj3ZvA\/W8RgFW7jIP1t+bPnA1JDfktmTKJIEhPZsnLdPkEoAEoIVVBxxwQJhQoFWyJ\/K3lIprzaolU1dffXXMnj07NATpsRXSMkx62RTAhiZ8IUNnJgCTV1YR2JXFnsve6jQtB7yUsCPl+qggkwWba1\/+73044uFG7PyU+7KG2jzpprwOqDGZZ\/0ue6sPOqaUlilGpw6WYUe\/N\/3yX8he\/j\/7GfcvY3P1qMN\/XBhi6q56t0JD\/Kq1Jfk+cG3OMDOAT7iwodpy+sUvfjEb1YUDpvb4075888pEjaGye\/ZSM+E+8yKs70XRcFEBX5orcKbhAlTh0O9+97s4\/vjjQ5psuJZiWa5lOMhOy\/4q3EgRTdpMv\/zR5M8\/\/\/zerNwXF100Ok47beN8b7LOWkw3GjbtH19mzJgRTAkmxYCEiT1hBqJOHSzLmYH5H338nzZtywyuHf4vy7uhv+uuXlGouuz8lrW5ppTi0EMPDRqrdajWpPp6gImlwiuAaHIJQAIJw\/3nPe95eeG\/IS97K1AuWu6JJ56YP+9Cc0WWXBnK2RZomGxip6TNHMG2yqUtewa4gYwdWiXcMu7VERNj6VHBUXWgma6oQhWaW11X1LgsRaHZs44IFJdVz3pp5tERmT5WuRVVT5b5OX922rRpeV2vvNGmaeJPe1p3zJ9\/b2Vv\/UcYhlolYfJNZKseaO6A1LGJeGv4D4CZTISpU0prXx1MnPuX2DMu76PoXSEQl1cl66WbFncFenWcHYX2W3xJoCpU3++4xsaBPpQWBep7UF30x3+jJOarwv\/nP\/\/uKmTkj2K6aFv+\/+MfsabawJyYGgujKwrdGz1HXU+P2VGoO3pWCfRsarWxdUKU8PUVHNE4MTKlkyJQtPqPPaBQq3HW7XDLaK5m+adPnx7AjY3TZBNAMCte2GBnldUCNDGaBHA599xzw7GBNFwrDOyuAr4lTnFpvGyyJrZmzZoVc+bMKY\/6XOteacAmtZgRgNm8efPCB\/n6Ao3QBb7Qosvradoa9t57N6IqTibP2Inl2bXwPsBIE28mHUhXNdnlvFthUacOcKF\/6o\/\/eJ1SyrxXBwcdtKTq5JZEK\/wnZyYm2cBLHXT43z\/vV+5bgJW78tAlxPbbbx91\/hf\/dcFdBlzZA\/fcc89gDwSWhLm5kLTYt73tbeELpmeeeWY+xYpt9Yorrohdd901C7YJHOcAlLjWuFrCxIZKC3UuK63YcWyWYJVwXENuqwguv\/zy4NqMAJQ8azdiCtG57LPPgth55+szpZTyF2o9U0ZavJUVzYRngLW5TJ06aObIwPd4zOSSUsq8Vwd77rkg2709WxH\/1YcVG5bGUQbKWzr8L5wYrAtUC7UWl0kQhtT531rMtSPUMuA6mCwTQkNjcZwRQNM1JJ45c2Z4xp9ma4WApVtWDgBgQ2kASuPYbbfdwsaCqVOnCt5H7LSWbgEuWp9GwhzRF6DtLrqrHBWqLlv4WZ720Y9+NG699dYWQvcfBJ87dVB4U\/jPLX4rdle3Dlrj\/8uj0wb6r4fV5X\/\/qbaP7zLgmlKKYiutZ9FQvX7vmgZa1p2apAGCZsHrJgTbO9nJbH017CqfbDGUPvvss+OII44IqwPKEE6abLg0X3ZZ38uiJTvsBYAj767TglfMj90WHN9HCz4+PzLNr9xemv\/mBYEWPL7yK7RPdY3eW7mFXltdV3RIFQ+dP3ly\/VUDXs+fv1tlc+2hAQM1PVBGk3RN3nkyZq2rg23mx4MLvtdHC0ZVfET7V24vzb+xqoOKblxwbRRacGP1vKK\/LvhZFPrzgt8Gwn803HWQ0trXBt684PnxgQU79ZF79PgFp0ah1y7YP9CxC3aPQm9csE+gAxa8MgodsuCQyDSCbaC5Tayt933gah2mGWy2ze9\/\/\/t5goqm6aDqD3\/4w33lswzJ4SommN7ylrdks4B982yzbFh9AasL97Nnzw49fHW73M9zWi27JM2W2cAJWrTao446KhYuXBiGd4DIRNjBBx8ctsqWhEwIDSWd1sJ63P7eX\/JXd9mlnbmAt4ZD9WflulMHz8zHTdZ5Opx10OH\/yPK\/tIN1xe0DV8BmMstEE22SzRWo+hKA5VClwLZsOh8A0UZppTTU8nxFLjvs\/KpHNEvaHM4ntIE0E4CTter2XuBrWZYtszTk5rhrw71yAQ0rJspQvjnfnTpo5siavV9ZHawm\/1vKbKcNPDOvHhqoDbTExLUkUB+4yi\/t0KdVGPtNNjxhigAABYBJREFUFNBiMcFw3vNCzgSgkbKdFr9W3Dlz5oRhfnN6JS4Nl7Za7usuLbducqg\/W5euO3UwsrXZ4f\/I8n9devsy4Lq2F2zHHXcMS7eYESwJYxMuM\/Ke8Yvqn3WmwjBFVLf5TFk7xth83Q8XacjsyCN5XsKaLis+d+pgTXO19fQ6\/G+dV0Mdcq0HV8u1bEVlorDEi63WNlkmBCsMDAVp4Wy77q1QMFEGaK1SMKkGWJ2VYOWC6+EG2aGu5KFOf32rg6Hm52DT7\/B\/sBwbnvBrLbiaUbfDixZ62GGH5SMSsczKA2ckOJsAyLJx2oxgX7+DX2islnjZZWZNL8A1SccEYm0ts8Qb3vCGPKHndCppdqh\/DnTqoH++DJdvh\/\/DxelVe89aBa6G+OzBDkwx6WXHF9BMKYWdNnaNmTSy8cAkmPDW3mKN9aR2jdkuaVJu5syZYTeO55Z9HXjggXlpGG3WsNYuMuttxe3QUg7gaacOlvJjuK86\/B9ujq\/6+0atetThj7lo0aJ8EhfN0jDeBBkQBJBO77K11rVtpfb201At5QLAdomllPLSLpqqIxGtt3X4ik9+MxOYMJsyZUr4dIrVC+xX\/a3xHf6St88b16s6aB+29+Wkw\/8+VrT9xVoFrlYMWMYFUJ2QVYDQri\/gCFgBKg2VJgs8uVtssUU+UMW95w5RUTO0WLvIgKi4AJufOI5SBMJl0kv4DkV06mBkpaDD\/5Hl\/2DevlaBq33gNElg6ihE577SMIFlSj1aKZAslFLPeakppWAycC4CcAWyKaV8DkJKPWHYrzwT10lg7LVA+bTTTguL\/ws51WowDF7XwnbqYGRrtMP\/keX\/YN6+1oCrYbyhv62wtEuLsQ3nnapjqESjBZoKn1IPYLpGhvmelVUAwgJR6fjigg0LKaW828w1s0I5UMY63xkzZsSMiuxMs51Xmusjrbt1sHbUZof\/a0c9lVyuFeDqiwdnnHFGWCYFSFEdGIGmITzNU8EAZ\/M1zTSlHtBlVhCOPVY6zAA0W67vgJkQY3YAwrb\/AljkaDQ718Rd36hTByNb4x3+jyz\/V+XtawW4Otv1kksuCV8zMIMPCGmsjioDiO6BKVAtTHCNaKwp9YBqSj2mAOAsjhUFwFU4GuxNN90UVgrQiH3dVVo0We76Tp06GFkJ6PB\/ZPm\/Km9fK8D1+OOPD8BnJ5PPptBSAST7J3srYAWWvrXFBFAYAThTSsFGW\/zYUpkWxPE1AAd8A1YAa4WBdLfbbrsM5IDZlxVK3PXZXUfqYK2twg7\/176qa2twPeigg8KEki8iWNfqA34ppQCoQNRMfko9WikgBZCeAdqUeiaxUkr5kx8ppbxigEkgpZQPVLZEi4b6zne+M0x2pZTi2GOPDaeBMQ3QYG+88cZYn\/916mBka7\/D\/5Hl\/+q8vW3B1c4pW1MdEmPyCmj6gio7Ke2SBmuHlW998SvgSiN1DXxdYw7QRcLxA9LAlKZLS3XMYUoprJt16paJq9\/\/\/vdx1VVX5e8cSWN9pE4djGytd\/g\/svxf3be3Jbg6F8CZANb0Of4QUNJGgawCA1ouEN1jjz2CawifUo92CkhNYInDX1jXgBWg0lbN+jMR+CKt81UtcbG7ix2XnZXGbBJN3PWR1vY6WNvrrMP\/tb0GI9oOXPXWzgCw7Gry5MnhkGlf8ASMNgpwgWdKKdhKTWillHJNpJTy2lXPeQDYlFLWQFNK+ZR\/wLzvvvuGdbI2Cuyyyy7hkzLOILChwMSBuOszdepgZGu\/w\/+R5f+aenvbgavdVZZB+WSMT1JbZgVAASatkxYLAN2bgEopZV6klIK5wOQVAEa01pRSAFD34iAgzTQgXbZVX3GlreaEOn+iUwcjKwQd\/o8s\/9fU2\/8fAAD\/\/zu9vQgAAAAGSURBVAMAIoQ+kgWhVpIAAAAASUVORK5CYII=","height":198,"width":792}}
%---
%[output:5a23041b]
%   data: {"dataType":"text","outputData":{"text":"\n✓ 結果を step3_results.mat に保存しました\n","truncated":false}}
%---
