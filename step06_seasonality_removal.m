%% Step 6: 季節性除去と相関分析
% 目的：カテゴリ間の時系列相関から季節性の影響を除去し、
%       「真の関連性」がどの程度維持されるかを検証する。
%
% 入力: rawData.mat (rawData_dailySales)
% 出力: step6_results.mat

clear; clc; close all;

fprintf('========================================\n');
fprintf('=== Step 6: 季節性除去分析 ===\n');
fprintf('========================================\n');

%%
%% 1. 設定
set(0, 'DefaultAxesFontName', 'MS Gothic');
set(0, 'DefaultTextFontName', 'MS Gothic');
set(0, 'DefaultAxesFontSize', 10);

baseDir = '/MATLAB Drive/DAC25';
dataDir = fullfile(baseDir, '01_Data');
outputDir = fullfile(baseDir, '03_Visualization');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

%%
%% 2. データ読み込み
fprintf('\nデータ読み込み中...\n');
load(fullfile(dataDir, 'rawData.mat'), 'rawData_dailySales');
fprintf('rawData_dailySales: %d 行\n', height(rawData_dailySales));

%%
%% 3. 列名を明示的に指定
date_col = 'Date';
category_col = 'MajorCategory';
qty_col = 'POSSalesVolume';

fprintf('使用列: 日付=%s, カテゴリ=%s, 数量=%s\n', date_col, category_col, qty_col);

%%
%% 4. 販売マトリックスの作成
fprintf('\n販売マトリックスを作成中...\n');

sales_data = rawData_dailySales;
uniqueDates = unique(sales_data.(date_col));
uniqueCategories = unique(sales_data.(category_col));
nDates = length(uniqueDates);
nCategories = length(uniqueCategories);

fprintf('日付数: %d, カテゴリ数: %d\n', nDates, nCategories);

% groupsummaryで集計
fprintf('集計中...\n');
salesSummary = groupsummary(sales_data, {category_col, date_col}, 'sum', qty_col);

% マトリックスに変換（行:カテゴリ, 列:日付）
salesMatrix = zeros(nCategories, nDates);
for i = 1:height(salesSummary)
    catIdx = find(uniqueCategories == salesSummary.(category_col)(i));
    dateIdx = find(uniqueDates == salesSummary.(date_col)(i));
    if ~isempty(catIdx) && ~isempty(dateIdx)
        salesMatrix(catIdx, dateIdx) = salesSummary.sum_POSSalesVolume(i);
    end
end
fprintf('集計完了\n');

% 販売データがないカテゴリを除外
validCats = std(salesMatrix, 0, 2) > 0;
salesMatrix = salesMatrix(validCats, :);
uniqueCategories = uniqueCategories(validCats);
nCategories = size(salesMatrix, 1);
fprintf('有効カテゴリ数: %d\n', nCategories);

%%
%% 5. 元の相関行列を計算
fprintf('\n元の相関行列を計算中...\n');
corrMatrix_original = corrcoef(salesMatrix');

%%
%% 6. 季節性除去（方法A: ダミー変数回帰）
fprintf('\n--- 方法A: ダミー変数回帰による季節性除去 ---\n');

monthVec = month(uniqueDates);
weekdayVec = weekday(uniqueDates);
monthDummies = dummyvar(categorical(monthVec));
weekdayDummies = dummyvar(categorical(weekdayVec));

% 切片 + 月ダミー(11個) + 曜日ダミー(6個)
X = [ones(nDates, 1), monthDummies(:, 2:end), weekdayDummies(:, 2:end)];

residuals_A = zeros(nCategories, nDates);
for i = 1:nCategories
    y = salesMatrix(i, :)';
    b = regress(y, X);
    residuals_A(i, :) = (y - X * b)';
end
corrMatrix_A = corrcoef(residuals_A');

%%
%% 7. 季節性除去（方法B: 7日間移動平均）
fprintf('\n--- 方法B: 7日間移動平均による季節性除去 ---\n');

residuals_B = zeros(nCategories, nDates);
for i = 1:nCategories
    movingAvg = movmean(salesMatrix(i, :), 7);
    residuals_B(i, :) = salesMatrix(i, :) - movingAvg;
end
corrMatrix_B = corrcoef(residuals_B');

%%
%% 8. 結果の比較と評価
fprintf('\n--- 結果の評価 ---\n');

upper_tri_mask = triu(true(nCategories), 1);
original_coeffs = corrMatrix_original(upper_tri_mask);
coeffs_A = corrMatrix_A(upper_tri_mask);
coeffs_B = corrMatrix_B(upper_tri_mask);

corr_threshold = 0.5;
high_corr_pairs_original = sum(original_coeffs >= corr_threshold);
high_corr_pairs_A = sum(coeffs_A >= corr_threshold);
high_corr_pairs_B = sum(coeffs_B >= corr_threshold);

if high_corr_pairs_original > 0
    retention_rate_A = high_corr_pairs_A / high_corr_pairs_original * 100;
    retention_rate_B = high_corr_pairs_B / high_corr_pairs_original * 100;
else
    retention_rate_A = 0;
    retention_rate_B = 0;
end

fprintf('\n========== 結果サマリ ==========\n');
fprintf('元の高相関ペア数 (r>=%.1f): %d\n', corr_threshold, high_corr_pairs_original);
fprintf('方法A後の高相関ペア数: %d (維持率: %.1f%%)\n', high_corr_pairs_A, retention_rate_A);
fprintf('方法B後の高相関ペア数: %d (維持率: %.1f%%)\n', high_corr_pairs_B, retention_rate_B);
fprintf('================================\n');

% 季節性除去後も維持されているペアを特定
[row, col] = find(upper_tri_mask);
maintained_idx = find((original_coeffs >= corr_threshold) & (coeffs_A >= corr_threshold));

fprintf('\n--- 季節性除去後も高相関を維持するペア (方法A) ---\n');
for i = 1:min(10, length(maintained_idx))
    idx = maintained_idx(i);
    r_idx = row(idx);
    c_idx = col(idx);
    fprintf('%2d. %s vs %s (除去前:%.3f -> 除去後:%.3f)\n', ...
        i, string(uniqueCategories(r_idx)), string(uniqueCategories(c_idx)), ...
        original_coeffs(idx), coeffs_A(idx));
end

%%
%% 9. 可視化
fprintf('\n結果を可視化中...\n');

fig1 = figure('Name', '季節性除去分析', 'Position', [50 50 1800 1200]);

subplot(2, 3, 1);
imagesc(corrMatrix_original);
title('(a) 季節性除去前');
axis square; colorbar; colormap('jet'); caxis([-1 1]);
xlabel('カテゴリ'); ylabel('カテゴリ');

subplot(2, 3, 2);
imagesc(corrMatrix_A);
title('(b) 方法A後（月+曜日ダミー）');
axis square; colorbar; caxis([-1 1]);

subplot(2, 3, 3);
imagesc(corrMatrix_B);
title('(c) 方法B後（7日移動平均）');
axis square; colorbar; caxis([-1 1]);

subplot(2, 3, 4);
diff_A = coeffs_A - original_coeffs;
histogram(diff_A, 50);
title('(d) 方法A: 相関係数の変化');
xlabel('変化量'); ylabel('ペア数');
xline(mean(diff_A), 'r--', 'LineWidth', 2);
grid on;

subplot(2, 3, 5);
diff_B = coeffs_B - original_coeffs;
histogram(diff_B, 50);
title('(e) 方法B: 相関係数の変化');
xlabel('変化量'); ylabel('ペア数');
xline(mean(diff_B), 'r--', 'LineWidth', 2);
grid on;

subplot(2, 3, 6);
scatter(original_coeffs, coeffs_A, 20, 'b', 'filled', 'MarkerFaceAlpha', 0.5);
hold on;
scatter(original_coeffs, coeffs_B, 20, 'r', 'filled', 'MarkerFaceAlpha', 0.5);
plot([-1 1], [-1 1], 'k--', 'LineWidth', 1);
xline(corr_threshold, 'g--');
yline(corr_threshold, 'g--');
title('(f) 除去前後の比較');
xlabel('除去前'); ylabel('除去後');
legend('方法A', '方法B', 'y=x', 'Location', 'northwest');
axis square; grid on; xlim([-0.5 1]); ylim([-0.5 1]);

sgtitle('Step 6: 季節性除去分析', 'FontSize', 14, 'FontWeight', 'bold');
saveas(fig1, fullfile(outputDir, 'Step6_Seasonality_Analysis.png'));

%%
%% 10. 結果の保存
step6Results.corrMatrix_original = corrMatrix_original;
step6Results.corrMatrix_A = corrMatrix_A;
step6Results.corrMatrix_B = corrMatrix_B;
step6Results.retention_rate_A = retention_rate_A;
step6Results.retention_rate_B = retention_rate_B;
step6Results.high_corr_pairs_original = high_corr_pairs_original;
step6Results.uniqueCategories = uniqueCategories;
step6Results.salesMatrix = salesMatrix;
step6Results.uniqueDates = uniqueDates;

save(fullfile(dataDir, 'step6_results.mat'), 'step6Results');
fprintf('\n結果を保存: %s\n', fullfile(dataDir, 'step6_results.mat'));

fprintf('\n========================================\n');
fprintf('=== Step 6 完了 ===\n');
fprintf('========================================\n');

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":47.2}
%---
