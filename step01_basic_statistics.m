%[text] ## 書店データ分析：Step 1 - データ理解と基礎分析
clear; clc; close all;
%[text] ### 1.データのインポートは「rawData.mat」を実行
%%
%[text] ### 2. 基本統計の確認
% 期間の確認
dateRange = [min(rawData_dailySales.Date), max(rawData_dailySales.Date)];
fprintf('データ期間: %s 〜 %s\n', ... %[output:group:37b3bd2d] %[output:0e760047]
    datestr(dateRange(1)), datestr(dateRange(2))); %[output:group:37b3bd2d] %[output:0e760047]
% 店舗数
nStores = length(unique(rawData_dailySales.BookstoreCode));
fprintf('店舗数: %d店舗\n', nStores); %[output:75217f7d]
% カテゴリ数の確認
nMajorCat = length(unique(rawData_dailySales.MajorCategory));
fprintf('大分類カテゴリ数: %d\n', nMajorCat); %[output:3f886348]
% 総販売冊数
totalBooks = sum(rawData_dailySales.POSSalesVolume);
fprintf('総販売冊数: %d冊\n', totalBooks); %[output:06bdf47f]

%%
%[text] ### 3. 売れ筋カテゴリの分析（top10）
% カテゴリ別集計
categoryStats = grpstats(rawData_dailySales, 'MajorCategory', ...
    {'sum', 'mean'}, 'DataVars', 'POSSalesVolume');
categoryStats = sortrows(categoryStats, 'sum_POSSalesVolume', 'descend');

% TOP10表示
top10 = categoryStats(1:min(10, height(categoryStats)), :);
fprintf('\n順位 | カテゴリ名 | 販売冊数 | 平均販売数\n'); %[output:615eef0f]
fprintf('----------------------------------------\n'); %[output:8d5f9558]
for i = 1:height(top10) %[output:group:1a284526]
    catName = char(top10.MajorCategory(i));
    % 文字化けを防ぐため、表示を調整
    if length(catName) > 20
        catName = [catName(1:17) '...'];
    end
    fprintf('%2d位 | %-20s | %6d冊 | %.1f冊\n', ... %[output:0dec218c]
        i, catName, top10.sum_POSSalesVolume(i), top10.mean_POSSalesVolume(i)); %[output:0dec218c]
end %[output:group:1a284526]
%%
%[text] ### 4. カテゴリ販売の可視化
figure('Name', '売れ筋カテゴリ分析', 'Position', [100 100 1200 600]); %[output:3a9fe3aa]

% サブプロット1: 販売冊数TOP10
subplot(1, 2, 1); %[output:3a9fe3aa]
bar(1:height(top10), top10.sum_POSSalesVolume, 'FaceColor', [0.2 0.5 0.8]); %[output:3a9fe3aa]
xlabel('カテゴリ'); %[output:3a9fe3aa]
ylabel('販売冊数'); %[output:3a9fe3aa]
title('カテゴリ別販売冊数TOP10'); %[output:3a9fe3aa]
xticks(1:height(top10)); %[output:3a9fe3aa]
xticklabels(top10.MajorCategory); %[output:3a9fe3aa]
xtickangle(45); %[output:3a9fe3aa]
grid on; %[output:3a9fe3aa]

% サブプロット2: 構成比（水平棒グラフ）
subplot(1, 2, 2); %[output:3a9fe3aa]
numTop = min(10, height(top10));
topSales = top10.sum_POSSalesVolume(1:numTop);
totalSales = sum(categoryStats.sum_POSSalesVolume);
topPercentages = (topSales / totalSales) * 100;

barh(1:numTop, topPercentages, 'FaceColor', [0.3 0.7 0.5]); %[output:3a9fe3aa]
yticks(1:numTop); %[output:3a9fe3aa]
yticklabels(top10.MajorCategory(1:numTop)); %[output:3a9fe3aa]
xlabel('構成比 (%)'); %[output:3a9fe3aa]
title('カテゴリ別販売構成比TOP10'); %[output:3a9fe3aa]
grid on; %[output:3a9fe3aa]

% パーセンテージを棒の右側に表示
for i = 1:numTop
    text(topPercentages(i) + 0.5, i, sprintf('%.1f%%', topPercentages(i)), ... %[output:3a9fe3aa]
        'VerticalAlignment', 'middle'); %[output:3a9fe3aa]
end
xlim([0 max(topPercentages) * 1.15]); %[output:3a9fe3aa]
%%
%[text] ### 5. 日別・カテゴリ別の集計（次のステップの準備）
dailyCategory = grpstats(rawData_dailySales, {'Date', 'MajorCategory'}, ...
    'sum', 'DataVars', 'POSSalesVolume');

uniqueDates = unique(dailyCategory.Date);
uniqueCategories = unique(dailyCategory.MajorCategory);
nDates = length(uniqueDates);
nCategories = length(uniqueCategories);

% カテゴリ×日付のマトリクス作成
salesMatrix = zeros(nCategories, nDates);
for i = 1:height(dailyCategory)
    catIdx = find(uniqueCategories == dailyCategory.MajorCategory(i));
    dateIdx = find(uniqueDates == dailyCategory.Date(i));
    salesMatrix(catIdx, dateIdx) = dailyCategory.sum_POSSalesVolume(i);
end
fprintf('作成した行列サイズ: %d カテゴリ × %d 日\n', nCategories, nDates); %[output:5030fb10]
%%
%[text] ### 6. 簡単な相関分析（次への橋渡し）
validCategories = std(salesMatrix, 0, 2) > 0;
validSalesMatrix = salesMatrix(validCategories, :);
validCategoryNames = uniqueCategories(validCategories);

corrMatrix = corrcoef(validSalesMatrix');
corrUpper = triu(corrMatrix, 1);
[sortedCorr, sortedIdx] = sort(corrUpper(:), 'descend');

validIdx = find(sortedCorr > 0 & sortedCorr < 1);
topIdx = validIdx(1:min(3, length(validIdx)));

fprintf('\n関連性の高いカテゴリペア:\n'); %[output:2f44add0]
for i = 1:length(topIdx) %[output:group:3539cd02]
    [row, col] = ind2sub(size(corrMatrix), sortedIdx(topIdx(i)));
    fprintf(' %s ←→ %s (相関: %.3f)\n', ... %[output:5ba0852b]
        char(validCategoryNames(row)), ... %[output:5ba0852b]
        char(validCategoryNames(col)), ... %[output:5ba0852b]
        sortedCorr(topIdx(i))); %[output:5ba0852b]
end %[output:group:3539cd02]
%%
%[text] ### 7. 結果の保存と次のステップ案内
% 【修正v2】TOP10カテゴリとその販売行列を正しく抽出

% TOP10カテゴリ名を取得
top10Categories = categoryStats.MajorCategory(1:10);

% ismember()を使用してインデックスを正しく取得
[isMember, top10IdxMapping] = ismember(top10Categories, uniqueCategories);

% 全TOP10カテゴリがuniqueCategories内に存在することを確認
if sum(isMember) ~= length(top10Categories)
    error('一部のTOP10カテゴリがuniqueCategories内に見つかりません');
end

% TOP10の販売行列を抽出（順序を保持）
top10SalesMatrix = salesMatrix(top10IdxMapping, :);

% 検証: 行列サイズの確認
fprintf('\n【TOP10データの検証】\n'); %[output:56f9e58c]
fprintf('  TOP10カテゴリ数: %d\n', length(top10Categories)); %[output:40aa3780]
fprintf('  TOP10販売行列サイズ: %d × %d\n', size(top10SalesMatrix, 1), size(top10SalesMatrix, 2)); %[output:37b96a32]
fprintf('  各カテゴリの総販売数:\n'); %[output:42347582]
for i = 1:length(top10Categories) %[output:group:525bca3a]
    fprintf('    %d. %s: %d冊\n', i, char(top10Categories(i)), sum(top10SalesMatrix(i, :))); %[output:9508a64c]
end %[output:group:525bca3a]

% 保存データの構築
analysisData.salesMatrix = salesMatrix;  % 全カテゴリ（後方互換性）
analysisData.uniqueCategories = uniqueCategories;  % 全カテゴリ（後方互換性）
analysisData.uniqueDates = uniqueDates;
analysisData.categoryStats = categoryStats;

% 【追加】TOP10専用データ
analysisData.top10Categories = top10Categories;
analysisData.top10SalesMatrix = top10SalesMatrix;

save('step1_results.mat', 'analysisData');
fprintf('\n結果を step1_results.mat に保存しました\n'); %[output:1316368d]
fprintf('  - 全カテゴリ数: %d\n', nCategories); %[output:3e92dcb2]
fprintf('  - TOP10カテゴリ数: %d\n', length(top10Categories)); %[output:02546be7]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":36.3}
%---
%[output:0e760047]
%   data: {"dataType":"text","outputData":{"text":"データ期間: 01-Jan-2024 〜 31-Dec-2024\n","truncated":false}}
%---
%[output:75217f7d]
%   data: {"dataType":"text","outputData":{"text":"店舗数: 35店舗\n","truncated":false}}
%---
%[output:3f886348]
%   data: {"dataType":"text","outputData":{"text":"大分類カテゴリ数: 7051\n","truncated":false}}
%---
%[output:06bdf47f]
%   data: {"dataType":"text","outputData":{"text":"総販売冊数: 4706637冊\n","truncated":false}}
%---
%[output:615eef0f]
%   data: {"dataType":"text","outputData":{"text":"\n順位 | カテゴリ名 | 販売冊数 | 平均販売数\n","truncated":false}}
%---
%[output:8d5f9558]
%   data: {"dataType":"text","outputData":{"text":"----------------------------------------\n","truncated":false}}
%---
%[output:0dec218c]
%   data: {"dataType":"text","outputData":{"text":" 1位 | コミック                 | 1383186冊 | 1.3冊\n 2位 | 月刊誌                  | 856595冊 | 1.3冊\n 3位 | 文庫                   | 630459冊 | 1.1冊\n 4位 | 児童                   | 325607冊 | 1.1冊\n 5位 | 週刊誌                  | 199600冊 | 2.0冊\n 6位 | 趣味                   | 180914冊 | 1.1冊\n 7位 | 生活                   | 137308冊 | 1.1冊\n 8位 | 文芸                   | 111247冊 | 1.1冊\n 9位 | 地図・ガイド               | 104020冊 | 1.0冊\n10位 | ビジネス                 |  99534冊 | 1.1冊\n","truncated":false}}
%---
%[output:3a9fe3aa]
%   data: {"dataType":"image","outputData":{"dataUri":"data:image\/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQIAAACBCAYAAAArHLSSAAAQAElEQVR4AezdCdxn1fwH8HOGtClJ0V+FrEX2ndLIVlEG0SA8JRpLRLRYJ0tapLFXlKlIKXsxqEwlUpaIUIgSRTKWoaT6\/95n5juduf2e5\/n9nm2e+c2d13yfe++555577vec7+e7nO+9vxnrr7\/+LS21PGjnwKo9B2akVeTf7W53u3TnO985vfCFL0xPetKTJu2p3WPzzTdPd7zjHSfkHs961rPS85\/\/\/LTWWmtNSHv4sO666ybtIv1cbbXVUgcI0jOf+cy00UYbTch9xtvIGmuskTbZZJP0yle+smzH295w12+66abp3ve+d8KX4er0U46no42XOija3WqrrcoYGwPXOo5z3babbbZZGhoaSg996EPT8573vNvwx5iag+ZiXG9c73\/\/+ydjHWX1doUBwatf\/er09a9\/Pc2ePbvuz232H\/\/4xye0xRZbpCaZuJh3m4u6FLzkJS9JRx99dGljzpw5CWNUC6bWA6PcYJiEW265pcNC2267bfrKV75S+q3v6JhjjkkbbLBBOe\/Ps5\/97HTkkUcm12+33XZp4cKF6Xvf+16hk046Kb385S9f7nptIHxwL\/esSb8N+m677VaEIs5p3\/0e8YhHpA984APpIx\/5yLDkvHrqv\/Wtby31nvvc56ZZs2alefPmpcMPP7zw+M1vfnMBA\/Wa1Ot4Pf3pT0\/u1RyrBz\/4wQk\/egE0k\/Wwww5Lb3zjGwsfPXv0J3gUzx\/lxm9oaCgZzyh705vedBteK4vztvhx0EEHpQ033LD0b7LHyz31FeEFwX\/Zy15WBNtzegbHu+66awFn9Zv0gAc8oNQ313bfffcyr+1HPbwxB+sy88ZY3\/e+941qy21XGBD8+9\/\/TmuuuWa64YYblutQ8+BpT3tamejHHntsatJrXvOadLe73W3ZJSYQ1GtOQsc\/\/\/nP03\/+85\/029\/+Nn3sYx9LixYtKtet0dE8L3jBC4qGLAVL\/xB6A\/OoRz1qaUlKd7jDHUqfCfYXv\/jF9Ic\/\/CGtvfba6QlPeEIBCMK8rPLSneuvv74I3iWXXFJKVl999aLdXfub3\/wmBV133XXJvdwzJoPtPe5xjzIhTAzngvRPg3e9612L4NEAD3zgA9NDHvKQZKI8\/OEPT8oQwVQPaN54441pvfXWKxP\/7ne\/e0JXXHFFuuc975lyzkl\/8Qs99rGPTV\/72tcKiAEklsTrXve6cgzUNlpqPbzjHe8oZfjyzne+M330ox+9zVgB4be\/\/e3pzDPPLHW1+5jHPKYAs3uhHXbYIX3jG99In\/zkJ9O5555bAFY9z6JtxKJ70YtelOL58QARLPzy7I4RQbv55pvTaaedVsi+MmBwyimnJHNFvZo8P1DtZ7xiTGxHG6\/6XuaC577LXe5S5paxMsccA05zy9gBcn0KMs9uf\/vbJ\/WvvvrqMgd32mmnMg\/q9mN\/uK174y++zhiu0kSX05rvete7ilB4IJrDw0Atx+hDH\/pQMvnqe5tAUK8b7b333unXv\/71surQDuo1AcOxtu93v\/ulxz3ucek73\/lOmfDLLuxj53\/\/+1+64IILCgpfeeWV5UoDSkiASimo\/nhGYPZ\/\/\/d\/y0oXL15cwO21r31tCvrmN7+Z5s+fn4477rhkku6xxx7FejAhr7rqquRZgwcEBi+XNdjZ+fSnP50WdqyPP\/7xj4lg\/v3vf0\/KUOd0+W8MTCzCYLIBBBMPTwilff3BL5aOfcD5wx\/+MP3rX\/9KM2bMSH\/961+T42uvvTa95S1vSZ\/5zGeKUB544IHFqthrr73Sn\/70p\/SPf\/wjvfvd7076\/N3vfjf997\/\/XWYpqasPBxxwwHKAASjwkYC+4Q1vSMbLs+KrdlhOW2+9delHeaAe\/vzzn\/9Mn\/\/85wvZd4l7E7Ju7kC\/42VsAYD+oZHGC3ixKAkwMreNgbnBnGft2Dq+053ulMwvAG7M1L\/Pfe6TEPDOOaeNOkBsn1Jl0WjL841GXApgqH38ZXFPGRBg8MYbb1wexMN4iJxz0UiOPSiN+MhHPrI8R2j32s8pJ6o\/BpLwR51rrrkmnXjiielTn\/rUbejUU09NBLC6fEy7hB4TTcqZM2eO2sYtt9xSrBBCZIBNQIP8wQ9+MJ199tlFO0LkEGw84PeFMNLy+FYDHPAc9cZdKlx66aVp3333LRMs55xoSAJKSwOG3\/3ud4lG\/\/Of\/5x+9rOfpZtuumnZeK3RsZw0uc4665SyGC8+9llnnVXAVRmriwZW\/ylPeYpLlpExJdyA+Je\/\/GWxjL761a+mc845p9wrKhpHZY5NcKDyt7\/9rQCwMry07YUIyvz58wvI2h\/tmhivAA31Y7yMOTLHCLVzYYYbLzTSeLFC8ZhVRnhZhRQZXrMIzVFbx+eff\/5ybg5A33777RN6\/etfnwD9wg7wv\/jFLy5KietmHPQpiBWpv0Cd9Q3ouVvm3o477ph23nnnqJqmDAiYMPxjD4JMBA\/D1HT8\/ve\/v2gNDNI7Aj5v3rzlNAZGd6MQDEzEMEjbJCaQSa\/tsdKvfvWr4gK43iAyj2kbk1\/ZcMRcN5nivIlsYHLOibZnZTzsYQ9Lj370o4s21SbXg2a13wQ2A0p7AEACnHNOBJSmA7hA1j2UoZxzCZTSXh\/\/+MdLN0zAX\/ziF8VU59qwFvQRUGnHsw4NDZWJZ3wIowtPP\/30Uma8AAnh5lrUAvGKV7yimLraNV62+qyc76qutgCN5\/z2t79drIwDO1YFV9Fc0Td1AAoBUvb73\/++zJGcs1OjEsEAstpglZgbyka9sFEBLykAYw6Qgr+bdYJ29gFDc4zqY89uvH70ox8VoQUEAAcvuWSe+S9\/+UsinLaOzRnjG10JoSbY22yzTXFz3ds+a5FrFHVjC9C5nviG18ZWn\/HA2M6fPz+qTh0QLLtjZ8fD8+0NrknUKSq+t20QrdBkMKT0QDRYzegf\/OAHcdmEbg2IPkajl19+efFhAQoBNFg0OIvGYNN2TDvCOGvWrHKZCaRMWwpYMbY554LqP\/nJT4oZrVwwbebMmUnMwvUGWlCP6dkk9wWAzHf35jebFKwHWp9QK0PO77nnniUybtIcd9xxiQl+3nnnJcDA\/DdpCAyXTV\/EVPQTGS\/nCD7wVgbITGbjgUeAw8QyLlwb9fDJczNB1aPl1aHlWQ\/GnsAvWLAg0XLaHQ9RIiZ9tMHy0L7xsDIQ4xXnu21zzmUVAYA671pbxHrhFrEWftexnsQjhoaGUnNsuh0bL23YMuHFa4wf\/rCCtWWu2DoGxoDDNcj4ACLlxoF1qx0BcyC9sGMdqFcTd9P8YG0aCyDGdXNsLtd1p8wiqG\/KzwMEJpvBc87EzTknAOC4m3ZX5oE8dK3xAYRrxkImJYTG2Lges+91r3sl5XziKLcFALQgQTKZBXVMelrdsiRTTb0vfelLNsnznXDCCQXBFXhumt4E0I6ADS1A64RwOU9IlO+3335JUJQQ2YbW1NaXv\/zlEnPBE6B59tlnFwvj0EMPLSCjDDl\/1FFHJRONRn7f+96X+J7AAaiKy4jSm2wsE3yueWq89C3nXDSyexsvfUYAy8Qi5MaF1lIH\/zw\/IAAu+OOezFjgMXfuXNX6IvcDKtqNCwGVcWSZ1eXOG6+cl7igtLIxUz4cGcdvfetbxTJThzthPIzFzA5IE1JxGM\/rPMJbLtWFF15YXC\/j1G28CD+XgiCzBIENPuK3cTAHbR1rF+WcSxCXUAsaqmM89Ulgkivivixs9cdKUw4EAh8iv1CMiRIdt2bsAaFtlNVbJg3Ni0njfei6XQMGmffZZ59lxQaLBsFsJvSyE50dLktnk0ziL3zhC3aLf2twTRaoazKVE50\/NClUNuCdwzKoQEBdE8Fz\/\/SnP020K21mmYcLZXCZcsoJLW1mS8tZ\/gQC7gWo1ME3QuDehEx\/lCHn1TXJrJgQGC5HtHHwwQen73\/\/+0k\/9NG9aR\/7MV7GJuesqJB+KyPsJmQpXPqHYAIOlgihMXk984Ed019gCol86+fSS4bdiOLTfMBGu4DgjDPOSFyTuIjrAmCBJx5GOfAxXszjl770pSVWgy9xvts2xouAOZ9zLitbXAwBVc\/NkgJG9VhQCEAdr41Tt\/ESmGMdAkbBVvwwfviEh6wPW8fujTyXNikbysmcUC7e4\/nwV0zGnHXsXC+kvmeJulMKBBhFwxEAQkTQTDQaSSTTRO42OTCPJoHOgigxSeMhYqstqGkFokmCJMHEqN\/c0tC0lWAggTr55JMTAYp6LAX+rcEDEPxqgEaDADWTyMAYUNeYKEDLxDGQno+G0iYgiAFWh0CZxPb106RzDRNUW0Gi93xuk6qfgXc9YbRCQEgtNxEg7VsFMQaeTT1WgUlSjxchc84YqGu8PDvNqJ2hoSGny3Ig94PA5pxLDAIvy8nGH35vPU6EFe+AMBdFdXxiffGXgYEy\/bWlYa2QcH\/wiuWlPMiyIwVirJQZP\/OLaYx\/3AblQfV4if4vXLiwLLMaLzEGoGSfe+AaY9HPeLlOXEBfXc+Vwzvzm1vJYrN1jL94ChjMDdaUZwW+rn\/qU5+qiWS+KTNnKdhSuPQPxeka4G9OLS0uG+4nK9AcVjBlQMAks5wkygzR+ZIG9z3veU+aN29eyY6C3CaWjgVBWpMFI\/hMTNs419xCYmDAfGsSs7BG2ua1hICGtF6O8Uxcg1bXM+FoGBqTKWqSGQSaiuBwB4CEa\/j4gnPq\/\/jHPy5aBQB6fkJC49ia5JbKXMPa2buzJOreNAGkD9ADUvrIYtCuiLyJ47rhSB8JMy0Ywig+YAlLv\/FDPyytGoecc1nJEGdg7poo+mu8jA3gct96vFgvXAFATWtGhBpIAcjPfe5zw3Wv+OL1OOGn6\/DJvgsBLBASdHSP+fPnJzEFE1mUnSARDO6O+eEaRJgIEh4bL6AAOFgnePmc5zynJGiZg+ojfI3xAkBWb4CSNghUzrnkYLiX+ehcP+MF6PHHvZD5Fu6cdoyttrnHgMg5MQNzigVnTChQQVcrUOYG0BYT8kzmj7F0bG4AC+QZ8RUYUIjiQkACKLJM9GXKgAByylw75JBD0nvf+95iTkPqT3ziE2Wpj6mH2UwuHQvCEBqAUDgPheNcc2uCzJw5s6xnMz9rMnEkqQhqNa9zTBuYZCLLNFVzAmMkbSW4x4xmeVjvjuPjjz++pImaIMDMeYJL6xjwiy66KC1atCgZrN91Ak38ce0QRgPE1ANkIscG3rPO70x6fdNnE5M5t9tuu5UlV5F2FobzwxFhAIyuxX+TwyoNTcQlMqFYWJ6Ndbb\/\/vsnmXaCffoAHGK8mLGuA8pAvB4vGjZ4TZMDDnw0qY2n88bF+NR9VR7XNbd8bhqUxpszZ86yMQ2eEAz9JBw0ofGr28ZXAGgcgQp+5pyLCwToCTFeAnCxKu5SPV5yGsxNvDNexo6w4k\/OOQFQNJ7xYl0YQyANJNyLsgFY5pV+skIoEs\/n2YGia4wLBXLZZZcVQDW+xtQWaH\/2Du5GWQAAEABJREFUs58tuSeAG3+smnmGBz3oQQl4aFfwM3g2ZUDghgSEUJgcjj2o5SMa0MB2E3J1mTbSQAmR64Yj2s\/kIIwmd12PX4ZpJkX46\/V5+yaNrDiI7Lgm\/WCNiG4bFNrjiU98YknPVY9QM21NaFYFwYbMENhzzZ07t2QvAhk+ucExkOoTMEJIs1o5cL1B1S7CN\/W5BFE\/zGB9ISj4SrD43jQz05cw6ecuu+xSsiD1Q9TYPdQVEHRfmki\/TD7P+eEPfzh5FiChXWX60ct4uQfLz5ip77qxkOCY2Iptt+v1iWYjHO7ZrGOuAD1ZivqCb3iBX+qyMPDIGOovq6IeL303H6T7xnhdfPHFJV\/C+juQGMt4ubfxQvaNgzGjnZF985dmp\/GNDaWiLmKlur97O88iA2DGFR88K4B3vTnpOVzHshILizkEwJQ5h6YUCNxwsol2hZY0pog5RvLLmYmEiSmEYRPdDwynVet2TVbldRk0r4\/tq6Musq+sV\/IstADt0ss1I92\/l+sHpQ5+ofp5uvF\/JH51q1+3NxH7U3EP\/Rw4IBDAIvzcECaVlzpoNWYgFA23xMO3NPUcAMr82am\/8\/S643TrzUAAAZOHySR3XaCJqSQRh3\/EL+ZX0bRcAhHziRwEQRt++HQkfZvIZ+21LfxvZrrxxcUMmN9M9rotsZZnPOMZJeFJObdOcJmZzLoT7VdeE\/dG0FMwuS4f6z5e1WM4a9asxC3hZiExj\/r8cPvevxA0FqSLOtwArp52mucEXlHUbW71a6zP1M91AwEEmMxXZJqbRPxbDBVV5gcKwBxxxBHlhSa+cD8MGqmuQXrb295W3rYTW5hupG\/6ONIzTMY5Qc0mEPBnBcOQWI1xinsLXrHgRNTFeZQL7ornAG6+vTIAw9pDllcFBAUnHbunOkHaESAjzCzBIIFMqeGAKeriEV7V4xfL3FFHlL0+P9w+39uKj7hD1BFnCCuoec5SLIq6za1+6V\/0Y7K2AwEE1setQAgUig3QPIJFAkTetTdJWAxI9LqeBONhrAECONrVzpHnX58+f\/GS16oFawSzBAtlmrFW4rjen6xzgmT6po\/6tiKJELDaJMRY\/aHJ+b7RJ0E5AS7xDtF85wRDrawIsnLt1JUDYdkPGVvLmSwJgiaib4lYPWQ+KBPcNQbIyoHVEOcAk3oIj\/DKOFopEU2XiMUaMT5ImSCy1QTHNamnPqtTULquJ8tTLAIQuUZEH8W+du13o6kcw4EAAkkXot+0iuURkVGDYVC5CuIEAACqmwAChibARBFLRFt\/WXxzuuTPN9ktKaoG3PKn9W3xijiu9yfzXOnIMH9oZBrXEmNdhSavBao+188+4deWFQhCIKqN70A72mHWA29JXMbFKgFhdN5KCSLI+qrMkqW8gSBJUZK1gD7AsAqiHiKUVm4s3wbJETAfCJ86TZK3z4K0PMrSYMYbH2Tp2JKbeziuyfKuuqL9ztf1ROYt2+GHpVDt6JelYoBn9aJuq943T5p9nKzjgQCCEHo+mOwzAk\/LmECYzbyE5MqtJBioyWLoytKuZCPCw9y2bg0sbQmvF2Pq52BVEeaRSJ36GmvsBFvU3X0Ir6Uywh31gCQgcE\/LXnIxxAWc9z0GlhNQR8pqYtUBGZrca7ViBoClriORhhXAHRSH0DZB8+4E16Gua\/\/Cf1xePu4hiceboJ7XnJJVyOdfuHBheWdErKkmAs6qUFc\/9I2log7gkYfAKrVUrh53RbKS+iwBboS6TRLf0q+poIEAAkxngplQNBw\/jG\/FPBelFiswAQWdZAFOBWNXpnvgl4lpG\/02cWlFx5Zk5RgI9AmGMdWtvjiWYMMXV0fdIPUJBV\/b2j0NHediC6QBNh9fxiOfX5o2S8W9aU\/5JVyAuMY5lp7gHVdDbIg1SFCl50Y9Wya5lGgAQREABgAg0cj6O0WhXpNkO8pbYcEBGWDmGpZSN8ILbou6gEZyklwQ4AcQkRwE9fRJsFRfCDpQ0ndWChenbr\/5PM1+TuTxQAABrcKfgrzQmW8JxSV9YBZfkSkmqGiCDTcB1F0ViJDLyCNIctQjGMdyYsJaap07d26y8hL8IIz4yIcnTCYsU5s7FnX63dLSkrQIsrc2gTb\/n2XAYuHLM60BCTcAoAMMYO4FKoIktgBkgIqgMAsh+sHCAQQEG6h4Xd08cD2hdU3UtX30upslgkzoZfuJNxFOSkSA0bXmFvM\/yLFyyVcsCIJuCVuC0nrrrZe4Q1KUWT8yW7kJrIL4shPQENyWTsw60160bbVLv6aCBgIIMFYUGepCb2mw3v4y+AYCAGCqlFWDI6YwFcydrveQsk3jeRWWP+ytQ+88yGCjhQTzCEHdfxNWmSxIpi1BJbQmsEBZXdc+sKXh1THRWWrKaUJbZGwIuYnv3QfWAOEF6KL73nkAPOqqR3gIu75zX9QneEBE9qR+87+BlCU79fQTYIhBiOUQfqsUtDLB03aTCLS2vJHKXNceIFKvSQQXGIlfOAdM3ROoOXY+51y+MbFgwYIEPCNOom7OuWRxGgv1a4p6ddlk7Q8EEBhkJqjlJ2m1kJdrYMLyy0Sg+au0CK0G4YdjKG3H9GXWRh1+Jn8ODQ0NRfFKuxWdl9tOk7IApDrb8uFpLpF1AsO6qh+SWe7YtTkveSWZaa+sJsIIUHyIlMXhZSFBQFaaFZ2oC7SZ7Xx3Wts9CRSz2ss1ACYEhGDz9Y0l6w+gs1K8PaffiDKw\/s\/S4OpoWx0aWSqxlQsA5bnFAGrrQZ8iRuA+wEUQksUjoMfXdy3tDxiGI\/kP6rmvecktyDmXd2vcQ19YDGIyrANgJjNUe4BTfMI+wkPXTAUNBBAEo0xwQm5CMQlZBl4oUaaO8wKL9rsR4bfERwvEeWUmqQ9TMqcdC0jG+ZV9a7J7oYjw05gjPY9cDBFyfBUhJyCub17DjCbcrA2BWWY2c59fzk+O+s5x35jpQIIr4I1F51kDNLlrHRMacYicc\/nOI1B3PYuAZmUVGmvWBBDh3gB\/13EJWCaAidlPSL0\/IIak7SaFMNPqgMnYsy6BgD6wXigaQMOaCXKeZaU9YEkhsXrcU6yDlQP8cl7yvUjzFGjop7cj9c810R4rVltTQQMDBKLWTLogQS0azKSNMlqJdhc0bDKXJUCbSOhgBsd5WsaxCeclDpOOaRnnV9YtoKTlaGzaqX4OZjdBDwCNc7QwjUWjcSf49sz+OF9vvUBD+GV3cidYa5bxrLPX9Qg\/ocF\/UXmC4jwLxX0IsmOrCpb3CAnh4SYAIVYL4AYgQJwLob7AsWuco\/0t71ka1C43pdsYihG4lkshTwEAGHeBT3OIdeK5vdYsECi+IRaAzAtWS865vGHq82\/KBRwpIO6CuaU9YKEd\/MenACl80o7rkOfXn6mggQECSM0U4wogcQEDAGUdI2hLuwsWNZlrkhpI5mjznMlowJSbSE2LgHnnXE0GWZ8MuslYH9f7k3WONq37U+\/zd31rAL+Y7QQ2zkv4McFpdBoRmDpH43pLlDa17i9Bx0qNJVnaUp2xkKU25jdfmrBGG+7LGiAQUaaucmazQCa3IOI9xjnq6bcoPsEFPKwYgsxlATQ0OrObCxHX2HINbI0Z4cQHSkO8ycoUIaUUjFmT1DXeQEqcQ0AWABlrIGUJ1Bxk6XAB5LuYV8gSIoDlNqgfbY80hvo5kTQwQIApBt1kRQJigi2Wthwjk8EKg3rqTxQxCZttmbQCXTSdictXjON6f7LOmejNPsUxPvCXBcwAIJ\/ZBPZVHBqMyWpZi18dk9HSIr6pxxJgaRFGQmfSR9v9bN2PW0Aw5NsbL+a6\/kkxJsAEN9rUJ2Y2gX7yk59c3k3QL1YAMMZf\/eMWAGsCSfAE6NS3SuJe2mQRAcRou95SFsz1nHP5vJmPmQBNIMi1MWY1cZmAkr4JMkqjZqmIW1iRwUNlgtkATz3zwz43xPIh5QSAAEK0PdIY1v2diP2BAgLmmoAeEjQkoPxYxwhqMxmZhv0wj0lsYrmG0IR14BgZUNuamNXMQ8E35iyBi+N6f7LOjeRfegbWUvRXXwkf\/lk5QARRmfcC1BNDsOrCpG0SgFCnX\/LsYgSyBwmJfokrAGvJQkzpaNOYcTNoTMJCaMISEbfRZzkNViUkjbEyzAFxBOPDAtJv9+BWaF+cIdq35RqIkwAMlgDrD5C7N8vDPQELzR8xAtYFoAFA6gNY4MRyARwEnQujr9pk4dD8ylgsOS8JurJ+WBvAD1\/QSGOovxNJAwUElrL4dYjGgsISSRwHiR0o75WJLAsmoQnm5RCD5WtD9fUmW31sXxlNwtUw+Py9OK73J\/OcfvRCLACAac0cGCDfblDmHJfJEhmrqhtZsVGnl3vVdbRtSY22jXJpte4ruFaDlUxDwM7Hpm1zXiJABIwpDazFGgTnrDoQdCY34STAUpwF91gO3CGrR1YH4r6x5QIRVM\/JQpHCHEDnWqAAOLlOvgLkOnPCtknu61NvzH\/zQD2uFKvEfOJyuIc4C1DQdt2Gc\/XxZO4PFBAwU5mPKBjO\/HQcxOxjqvXKVBOVJjQ5LR3KZGtaBN3aYpbqg2iwydWtTlvWOwdoYYLCMuMCEBzanfADFBqWdmZWEzramPYm1FYSbOu7ucbqQl120tXnp2\/+9eJkzIAEF4S2p625MASZEMtlcB\/kmAtgjri\/PgF3YKFtLoBYgZgV64DlQCFwT1ge3ISZM2eWj6RSHqwd7aLWNcDBMRDBE+RBot4mjiCP4yBmJBNtuOYJPo1oG3UMtCiyAavL43y37dCr90mvetWrknVzZmQLBt241FsZ4WFF0ZAEnFDTtLQ939oxDcvnZw0YX4JuqZhgUhCEmEC7IyAnwITNcdD6q62drrtxcTnUBgsizHzui\/uxDgioMXWeCY8AhXuqw31hvcg2BA76ytLRf32ySmMfCAAF1iqgY0G4XnuodQ3KUPT\/x\/ITIUbWf\/m1BtBxkLVs5mP\/rfd3xYZrz0hHLn0tWeIKTdZfC4Nfm4Cb+KM9KQGjPW0JFm1KSOzT6oRTrj7hsbRnfFkK3AZalmnO9xaHcCxWo4yWru\/99Ls8OM3e6HHltyekGguGElLuiCVELgVLTz6A+STmRPsjVohYhFwTQVYBQIpIHwk4C8FSqXbFGwCFPokhAQWulZiFDEmuqDaBX92\/ydwfKNeAxhbgQtbHaQJI7ThIIKq5bDRZDK5fS56se6zM7cpoJEzMZ24XII9xspUZyg8HojQnwab9AYgyIMLS4xYI6jGrWQwi+LS2tXvCyFJkIVpSpOm5ia7ff\/\/9l2Mf1+DjV55Z3APgLQ4gN4GwAgDuIc0tcUlcoiYWh8Aqf19yFGJxAAF9tgUmLFTxB8\/AzZTPAJQEZ\/VfXRaFtvtxYZd7kDEcDAwQWP+W0WatFkF7wSbry46DpA\/TGGPgVXvJBHMACBAgOQkEgCCx4Pj03i4U9acZ3VY9xJxeY401yk+vMfWdBwKEnnAhQTjtOQigiXwAABAASURBVKcOC4I14VoELGzrIKV7cA1suQfqWGFiZZg7LA\/zKeecvJAFTAh6kGVFQMPlyDmXX67SlvsDH310DRDhHmjL8q3+eh7nrDSIa0iP1i4w08ZU0EABAaQNAgxSS+XCR5mtCUaDTAVz23uMzAHCQNilOBNMQiGTk\/akxTfddNNlDSgjUDnnxDpwrWto\/JxzYh0QXqsHzPScc6JZmd3qugYY5JwLiJgDMk2X3aCzwzV41aZPSbM77oHz7ie4zM0EUO4FYGhqfavjBJYuc84ltyF1\/jHrLVOqD8C4DSwabVq1EqcQN7LUqUyb+m3OskbU5\/50mpqS\/wMDBAYJoppMOMcXM1D8R8eYa0lM8MfxVJNMMpPb4E\/1vafz\/cRxaG595Btbh+cqMOWNmXLEvyYwxpfPzkQHBDnnInxrdKyEnHMSPNSmc4DBvAAitrRzWvoPYIg7LD28zeaaxX9LrABmO6XCMvAKNJ\/fvbgA2tDfcDVpcsFoxK2wSgAIxAS4GOaevsnI5JoAJjErACF2IYlJjonO+EaD9uxPBQ0MEHillMmG6QCBzymJiN8pR11mmeCPxBIR5qlgbn0Py1FWEaxnt2CwhDNcA2Pk\/Q8lXDYWHE3KcluwYIHi8svNluxyziWQJyuQYBMkmpP2lQhE0Jn7BJdfbx8YABjBQysIGlRfXasMjoPqGMED73Hf8kvW6smcFGgEMjS3+3IFxKFkYrIGmPbKgMX+ndiDvntnI+ecBDBZPl7jZmFI6QZkhB\/pG4CTBMUlcM69vJUYfZvs7cAAQTAK8wEC7WGtWbKLRCMvJR1zzDHFdzOYUX+0LeQWezBhkZRl\/t5o1zXPH9muIDRZkkTKBQWdAOAsAx+OEdXnItDYzjGtxXzEEJwjOEx+5j5tT9CBO2Giwfn21v8BRs5LXgF23pzQnkAcAb\/oooscLqM6RhCFwInGZk0KRis3H7y3wjpg5S3oAJZjgMDsj3qsEvdh8gMmqcg0PtDyHNrShmxKloPlSDkMAMsHWcQT1JkKGjggqJlmEEwaPmJd3s++CWSi8WPlEniDzWD204a67QoCLnQnggYILLHR9D6BVgfKCBL+C\/oRLoJEq\/OzCR7hVwYwCLeIvTuxBtSXWmwOxHnLdu4laq9eUB0jUMaKY95LLGJNAiLtsQ6AFk3fXEaUgWmeWM2giLgxLFTP4BrWBCuGggJMrBarBcpZDNrmcsho9Iz6MRU00ECAgcxOWgcx5XLOiTZxrhdioqkHUGy7EZ+xW\/lwZYJYzD\/ajHaqj+v98Zzrx+oZrp9TUU6L0\/yi7V7zRvxmSVzcPcIC0Jt9AR6u85KPJWJCVtchsMaZdpWJyB0D6AjoEE5uWn1NuAaWENGvFv+pnGauixcAJ\/c9+OCDyzcRWIhcGeXIvg+R2vfylH5bdjQ\/jDXX0IoGzW8lArCZX6wNQMAy0E+AxWWIMdRflih3t3So88e8dn9kv1NU\/rNguSfiFKWgxz8DAQQGiilJiKQUM7Pi+b3UYnkKGXjRXygd50fbalfyhzXkJtPjWudjv5etYJjJycXQ9\/ptxHp\/POdMxl76sqLqAAD5\/lw5ws7M32CDDZLlXlaBYzkfgmyEd++99y6\/+ot3eKSO8fZKtI+ZGnft0NCeyTXOK6Nhc87JvCAoQJi1wH1I1b9wDaLorOsuSSddfX451A\/vOAAYFgKlggi7uBOtzpRnDXABrCqo6zkJN5Dw1SPWS1gK+kFBeWbaX3DQc7mOK+tFKjcHACxT+8i8EWtgJSH3DMG3FbfgrqjbKw0MEIgySyDyYhDUDgYwGZnyQf2AgDZoJoxGssysFRsY54KYerHfy5ZZykfkN4pG61sc1\/vjOTeVS0+9PHOzDg1II+KvCLkUXIISAiDwRvit\/AALqwa0orElQHjjY6a0J6Em5IQMH\/ndhCnIOfe3pZm1QUtrT3lQuAaWEINmd5YSzSGuRc45aZP\/brmSVUHIAY1j7QIe81Cbzvs4ikChxCjugWVJ9bg0SP6DJUT8sALhOq4Ni8DqgmNWRW3xsCKUs1KR5wdwAAIQAFDn+6GBAALBG2u9ElHkCpgIwQRmkwlDc2BolI9lC0QgN1Otvt6g1cej7atP45kYBlibcVzvj\/fcaP1Y0eeNFZ5Ky+VT0\/Y552XdInyyD5nRfHWTPOdclgst2dH4+AVQaNbU+Ucg+d2d3fKfxqbJuQjmRRx7D4BbUSqN8oewi+jbAhNvNXqHxBag5JwTMCDkLE6JQkDJ6odAteY9A0uBEItt+AgLULLMzfKztAhkAAltb+w9i2vNDdsgrgQrlJXqLUvAok3vMNhX3rReAcVILsNAAEEwqNtWtFmShkiy99tNtm71hisDJMh56aD8dq8mO25p\/BxgOvOFLRdy34JYBlp33pYgMaFzXqKVgb8y7gQ3QGyBUHLldt5550TwCRDBJXBiEASLoBAK7wMAGW0HcQPEBoajT\/\/xvLTof\/9OYgdR57r\/\/itpkwCbF+5jJUGZ9w1YBGICLEqvwOsP10ZAlJXj2QGKeMbJJ5+cxDtYFOIfYSGwFqKPllxdw4pQxjrKOSegaX7iBXcBuSfwVM92JJdh4IFAHsHBneAO8xNDmPe2vRKtZeAgLBPPtl\/\/q3kvlonJYqmIlmmeb4+X5wAw4DYQLFafFF37NCmByzknGpsQchnwV3m0QkgJE40bZQSPZRbHts0YgbKa\/nnT9elr1\/4kbbjaOilch9vlGYlwq8cVsHTNfXQMnCQQASag4zmAExAjmATaagSAUo\/GZtlwHdUVR9KODEh9ZwWwRs0\/lgBBN59ZRFY4uKie2y9EmaviDeIgvbgMAwcEtL\/BwBxmWDCduYihorbKMbgXYnLNnj07YTri0\/Zy3Uh1DJoIMvOSDzyIYDDS8zfPmbw+LyY4FkRj0nbqEmJ8lxhmCY9mU84ENz5iLUxyLgCtzMcmnIDBVi4AF4RbQKAII7eMtaidoG4xghD42O569yem9e9wx7gk3Wm1tcq+MaXZCR+rBPgAhEMOOSRZFtRXykgfABDT3xIhC9MxAFMm94HFoo+AQeNiFLYE3fJ1vexpLrsn14JVBVzEmXz6zTXAksuAR8qVdaOBAQJrw\/wu2gKierkIWkpa8U07D2+SqGPCOF5RRPCPbBOMlrGfGQ\/AfVUKIIj8E2z+v0oEA6CzxpyTxUczEmpakik9Y8atUznnJUvEovOCh\/x1Prw6AIH2DVNa+0EndVYIwuQfz\/bz11yYbrz5pkSord6wSlkFgJ+m58IAAFvPwA0isJ7P6gRQ8Ey+GKVvcg6sGngNmpvKmtCm+r7ApU3znatBAVpBEWjFP8DjE2+uUR8JkrIStK09ZbdyT+lKTISfz4gRHsOAQ0BpmgZdGQDwRVkTz\/GKpEFOMLKcZ0IT7CbRkJbWgve0GS3Gj2beG0NZeoK\/hJe1QOuz8pjNJjaz3j123HHHREsCChF2sQBv7yGrCSwJAsdkJ3DuyW0QVzAHtK0saDTXIOr1sr0l3VKqiUkx8c1DwU3CT3sDNMuF5imr0NKj5UjPz5IQeMRDjQAuzyyoSpntv\/\/+ycqF15pZEwAOH\/HJahE+Cb6yejy7OvIatKE9AOG+wEBgUjxhYIAAqjLhPSgrwNquY0iqDJk4gjGY43i6UP1Ckv6uzPEDE91SIJLRVxOhNflM2uC9ZyWkJjBNKDPQkhghZdpbGqPxfA0YWHALaEOCIqCmfZqQRUjQjC2yz\/Ii+ACBMGiHUAEe56ztRz9se3ENwkUYafu8uz063WHG7RNBZI3knMtvIHIFxANoZxaPfAQCibhBtDPeACnPji\/6BST03TNxOwi8Z0fcCTyTfAUQWbzejQAortUGt1jaM\/AAEMq5KdwK+\/g9MECAkSahBxM9NcH4RhgCWflwPmNF27Ae1JsupG9iBhKeaEX7zEiawoSdLv2Mfoy0JXA+PCrI2iTajGDH9Sa37\/3z4bkGkr\/40vjBtAUchBgJjiHr7vxvE9uSsJ9Ak5EnoYdQcAOtLpj8tHDOOQELbgIQWbBgQWItENLmS0fRr\/Fuc84lgEhwPY83Fa0YCHDWz+\/tSgFjFgp35w+L\/pzwzuqBZ7bcmTr\/AJf+yw8wx7lDeCCfRbDREiRriBLxfHgjngWEgIz6QJQVYmkxLAMA0Gm+vLE5MEDggWqCkkwvwmXyCORwFSy\/1PWmw\/6RVbzA5KiP+XdADSAYaPsmj3pWMxw7Nx2eo98+EERRba6bScpaO\/PMMxN\/lz9MAOo2+fs0JdOadjWu3Ax8yDknboP6BFAMAZ8AE81n0hNCpjAAEkvyUVH1gyYqRjBcfEHs4Pqbb0wX\/OM3Keqc9bdL0s2dDvz639ckbzwKiJq3QIvQd04lz7egA2AsAW4GHgA8x6wAFoZ6NSmzlMi6EHhkMXEZyIU2uEzkgaK0wjCwQAAh99lnn8QnZWaaOFYMMKhmWC\/7TDYBFQSFe7mmnzrNeEF9TDuyEABabS3IiRBhj3MmC1Aw+VcGYCCMkoRoQJpdMA3o+YFTkxTQcRfiexL4ScvT+sbWWHgngYD7zBfhJxg0IPOfBvUdQ0k94gmsDb60e2rLfZnn9oPWX23t2J2y7aWLr05nL\/pF2mzNDcs98cESqTcZmfUKCbSlSHOX4OOd5VQ8IMiADjioi9QxT61W4BEXmRvEZfA6PnDAR3Xnz59fVsQGCghMBj4oP4wvZZ\/ZiBkCMZaLmGkCOJjQC2E+LWIFQrDGMUb3cu1E1DlyGGtB2\/W5A979\/pXqq8lMX+4Pv5VZzNpR5l19pq2UcYLKWvCsQQSFOawulwJgMPVFz8WGgIE2Zd+JE5noTGcWguCj7yAaw4ULF5YknGjXdqJiBMPFD3be6DFprduvnh6z7n2W5SGo+5T1H5TkI+inZ\/MGoxUHc1W\/8IH2XtCxCvCG2V+TeYkXQFB9PCD8nt0xqq8Vm1BW08AAAfPHGistiYmORY+ZmDSDyWEpxzIUzVIzYaR9gGKiYTJUhs5iEPU1oYEfeNfbJV8vjnP1cb3vfH1c7zfPbbh2Tn9ZvCQC7Vx9vPz+jHTO5TcWIhwsA\/X7pfHWJ9AsqOZqgWOTE0jX9+ASiFpb0rKiw3WjzXoBa+2xJrwZSLDrdmPf\/dTx7gLz2PwAInG+3sozYZFMJFnbBz62o7WLB+YSQCPcvcayrDIsWrQoAYD6eShCbeJnlFNiAJG1FWW2AwEETCWmcqSn1lsmNW3OIsAsX5EVSfbwvZLrgskmFma6VqIHFOfXOX7eg1dPcx63ht1C9XG972R9XO+P59yTNlstIW3ok77po+PpSlJwmayi2ZJgmKxMfYBNy3frt5eQBIC5Rd4XYPU163EfjL14A5\/b+ybW45sWhuvwCK\/wzC8qTSRx7XxsxXa0dgWHzWP5A+YZV1a\/9E8\/0XbbbZf4+raOCTl3x2qB45pYEQRe3ZizVgvUYSHYBg0EEAgaQXxRZYy0RSaLAJR9QABtTTZLT8EEzyVCAAAQAElEQVSA8WwNEP9TIHI6kr7p43iesd9rWU6yAH1\/rxuJolvua7YLaGlkwsqyYxZ3E3AC4jyfWFvGtpuGt1YuLiQW4DNnLI1u9fQDj\/BqOowhq1Ofglh3LB6anYYnwFYVBPjECFi88+fPT8pdAxiiruM5c+YkikwsQX3WAwsMv51HQGIggMDDWGqRhLKw4\/sxw5DlI\/4Vwed7mhDK1O+HmFKY5RqBlpqJJhHUno6kb\/o8XYg2BgJ4OFqfrBB0c+FcC2jEfSTUjNSOMfF5OisEI9VzDq\/UX9Fk2bT2\/2Mf+NHw+krwo9zWsXJkv66rDBioh5rnnDefBwYIRIT585aTICfir3pwfj0zUnaV9EsP3ytZ+3a9tnzrQLzgoosu6vXyaVWv7UzLgeE4MBBAIEHCyygSJ+xLLkI+\/CDLDJIedNBB5Xv2\/E5lwzGkWc7k8gOXEjGYXRAXgjbrDXcMmGSLARFBNPvq8huth9tHUc9+kGwx18g7jzKJIXxNJnKUtduWA+PlwEAAwWh+Kb+T7yWIKHDYazQ2mMsUZVZZugEMUd5tKw4hMCRAJUgjZkFw9QEwWblg1qrDVZEjP2vWrKSe6DaQEjH35pk8CGviSDBNmzLU3EPbzF7BnxYUuo1Eb2VDQ0PLvj8IdHu7qnstVij\/nC+O6vYm8j7d7z6+0oEAgl5ZIFgkiNRr\/X7qWbkw8AI53iTjlxF+PufMmTOTTDFRYO+lSwbhcvg4BktBkEpASJadZTYBTjkRMuHk3wsYEXjAAMQsgXGFpNdKPuE3AxvLVO7VT79X5boEF8AKniH5IsrGyhPxKF8+ojS0ZzUEAGhzIu8z1v6NdN0qBQQjMWIs55j2rAUDLhOM2S7oxMzXHk3tZRmpooQZQMhxkPzhPQj57gRa5qMsMluug6Uv1wIXX8Xl1qy++upJ0CvuKVqM5NjbSqBxH8Di3i2NzgG8wmfZieI+4j\/KRr+yew3gbz44q71wIbU5kffR\/kRTCwTj4ChNLK3X0qQkI\/nf4hGy2LxEI6lJ82uttVb51RzxC9Fwpr1Jxw0AHHLkaXzHzps0ApQAIeecCDjXhluibfVYEVZAuAi77LJL8j18S2XeZBTYdN+WRucAC5FrGTXxN\/bHszUfjKFx085k3UfbE0EtEIyDi5YlLXFZukQ55yRP3osuLADfRuCOMPElMdHqrIKcc6L5JXuob8JEN0xEGkqZtfKwGLRnbR2oAAZr6FwLYKFd4AB4nGc1RHvtduo5wBWwSiWPhWKY+h70f8cWCPrn2XJXEFrCaE2bmU54CTHtT0C5AYCA5ifUgCHnXH7Dz\/vk6nIL1OEayKzzEokyN7K1\/g441GExuJ+lUnEE7SkDKjnnBAgk4ghWBUm60VZLt+UAXtYWFD7etlbvJSy0gw8+OPl4CAsurpzo+0S7E7VtgWAcnCR0tD7LQKDP+\/OyuAgvTS9fHECwFmhpQg4MCLQ6BN+xgKJrlavn5SgrDIRcXMBSKG0v8KRezkuAxKT12i5XQx2uCjdDwNHqCJIxJ4A5jscc2EuZ7XgGeJum\/FgeGgiI1YjZ1JbARN9nLH0b7ZoWCEbj0DDnfUxCnrxIM6EmkDkvcQ1YAy5jHgIL2twxcLAl\/ISccDuWO0+Ac84Ok9dxpU0DGCCRc07qS9mVIurVXKsONJlrAYc31kw4YGK50URE0nbFLkrD7Z\/lOIA\/Um+l6yL7ypar1OOBzFNA7fcWtBPWmDJtKnMPZF9Zj01PSbUWCMbIZia\/JT+ZimICXn4h9PIEmPsCfkx3gip6TPgJNkEl9M5zHYBGzjnJHaDtaXnAYkUBGFhy9Bk2bYoTAA\/1gJBVBenP0qoBRQAOV2KMj7XKXSZBzHIfsj9WBhjj2dXXrrWHok1bx8j+WO8zWde1QDAGztLE3mIklH69xpIgN0DAjgDnnBMXQTRazIB\/aH3ZdYCARgce9p23JbwyIwECd4MmVw5MLEdyK4CG6xzLkPReuW8D8kdlKlrBcI1JOYbHai9ZhTnQAkGfgz937tzE55YUxMyTwGPlQOCPINPi0p0JOC1Oa9v6ghDgIKgAQzmrwpYFoBsBIqwHYGDJie\/PqmBO5pzL57i0Ib7gjUuvrp522mlJLMKKBKvD15q119KtHMAbuRusNqX1sVRupHwkAsBcAONnFaiuy8ITJwqrzDnA77NgxtjxdKYWCPoYHaafaD2BJWw+dMFc5\/tfeOGF5Tf5CLfsP8JvAqjjFqwCAk+zhyCzJJj0OS\/JFeAqEGif2RK8YgEQbPWkJPM7TS7Xy1rkFpjArBH1WAg+7gFE3LOlWzkATKVoGwc\/f+dDtvx3v6Pg\/X+Ex00Bv7WFlCSNyd8Qq\/F2q\/biPBDgwhmPKPOTZZLBKIcom67bFgh6GBkawDffBP+Y7CaBoJCIMyL08v4tEYrgcxv82o5vH4hIWzUg8LQ74ZUWnHNOBJr14BwNDzgs9UkOMrEEJLkYrvd1G0lK7uFbdF6CAgC0HHDQD69a+9XdHh6prTIKB4CFJK+a8JlFIJFLLEfWqE+qjdJUT6flHvgYi63VB3EfwA+sogEp7CiObX1noa6jbCzUAkEPXDPYhDLnnGTxEXaTQqBQ9J5ZSBvQ5NGc6D4tQ8C5CYSfpnbMjWBRAACA4jy3QXTf0pNgIM0FKDbffPPE55e+zB1xLyAjRsAt8QITKyTu226X54BxA9K0PcsKePqMm9Ue8Re\/dSG2gnzYk1umBUAwuxP8845AEM0uGOy7ggAesRDVH41YGgRWDKhbXe8pyDuwmjBr1qwkoOh9BX0CPgCCe3nKKaek+p\/3UgCH83V5v\/stEIzCMVFe2X4+emJQWAbWigkvLUzgCbhj\/iBzngtAu4sZ2BJok5AQWzEQRORLmnQ555JcxFrYZpttEvfAp7pcByi0Z5B9\/9\/9fIeROctqcDxK91f508aGgHHXuHRezJKb4dVyx75n6YUwZPmV0AXTaGXfVAxyzIIDEt5k9VVpweKob3yBhzwOmtucMI4+gcaKNK6UR9SPLUFmVeqn+9sH\/pLVzAdKh+XX7fcLAYdy56O9sWxbIBiGawbQBGCi0x7eJzABvEzCVHeZT2ExHQkrYWf2G3wrAAaRoHqnQDDRgCL1gIDr7RN21oFjdWl+2gOYKOcGmLxAA7D4Nh1g8gXgaMe1LXXnACDgzuWcE0EVgwHEBN8rw3I2rOKI8TRbYHH5PiDyWXzuACuCVvcmKGvM+DWvq4\/VpeF9MxEQ6Et93j6rQn8IPzIPAAKLw9wyrygSPxijfpNYpSwa1zTP9XrcAkHFKcLPFCfMBP+AAw5I3hxj4jPFme+0gCU7E0yuv1UEP0klqUeZieFzXExS+4J3sgWZ\/YQagvP7gQMgEOQzQaUFuz8QMfhWDJiL3mazOmEC69fZZ5+dDjzwwMS9cG\/XVo\/Q7nbhAJOaQFoxYE0J7tpyF7h5AN+xwK\/XvqMJwmm1xlgZe5aENgQECabxjLq2gJ+fL5ho3CgMCkGyl5iOsVWvSdoCMlEO7IeGhpJlYTEf88\/ys\/EWN3CPWujdg5JhOUQb\/W5bIFjKMSYbX5KpJy2XKe6jIfxCy3QE0cATQrn9zEoCTTvTzDQFJGf6+1EN3wxw3iA5hvreRSDshNw14gZcArkBVgl0hbZCQIRVoIyFQCvQYMxX2YY+UCJQZPKp09LwHKD1jRdta9WGZUXwmOuCrzQ+II8WCBSBZynQwrbOAQTjJ1Zj7M444wzF4yICbWzrRrgIM2fOTDM7pJyrAIhsxSvMK+6EcxNFqzwQEEj+nO8ZElAmIoEl8HxCOf+E1IskBoJvTosTXpaB5UFxBG8E0jQChj5ACf1pBAMl4g\/ZDTjgYCG4FyEm8I69PswCoUm05V7Aw\/XOswQAimOkHywP+y0NzwH5AkDeWAFpwTUu1\/BXpBKnYX0BC\/VobFtAIH1bwNcXpIC\/+eNcL8Qq4WrWdYETwa7L6n1uBQVEYVA06uu\/eVTXG+\/+Kg0EJoifwmISMr8JsTJCRzBD+JloLAPHTDDWAcbTDiL8AEM0mWCzALgK1vkNnpiCusCAyWgJkLYh6CaYweUimKRQ3kdO7AMa1yHuBGvFRHTcUu8coLl9p4HwuMr48tWBqxUD34O0KiQOtHlnhUawz1gbH3X49IK1QEGMiABSBMaZyc9l1G6Q62hyc4bbEeW2fmvRPGMFOA7SN+3GcWzNB+2xEACAfdeaN\/oT9SKWwJKMsn63qzQQYCAh85Yexln\/J9yivJAY4w0cLeC8vH\/r\/MBAogh0F8RjuvMnTRATS10o7zpmpvPKJPzw8wCO4I57AwvlfFFJL1YeZAqyFFzT0vg4wDIDBNGKwJqVH7kABM1KjV8p5iYo438DC+Dsx1F8Wg6AmyuCg2I9xky5OA1FACDElIz1vvvum1iYFAPLwTIwcBFUtupEWbAGoz+2+mQ+EHLHyL44AWsACAADSsM8cd7yoi1iOZp\/6jkeC63SQOBFIaY4\/9EyoMCbgcNwguycHH4xAks0BoHwAwNbnxGTdupnt2lxS0vaEDQ0kSxZsQws+RkcIOMDpUxKIEDj+NiISeIlIhPPBAIgOWeXtDTJHDAm3ELKgPVg\/ICxoKHxBNLGlsY2RlK6jb8AJIAnqLrIhxcQFD9g1QENAWCam4Lh25sHgMb8cE1QCDlgijJCDUBqgfcpNG6obdRjrehLM78gzve6XaWBIJgkOAgIpJAabFqedrBkZEABBQtAIJGfLm7APaDZI79AsIlJCUCUWfKj4bXHn3cv6amy0fipwIVlYT3afU488cTyHoGJyC1Rn\/lp29L4OUCgCBYBsx\/CxPLytSfuAdePxjY2YkTOuTPQNg9YEo6NLbdCYpHALQtOG9oVSFYHceXcx6oEkpLsWueaZE4AAoLdPDfSsZUlQKKPI9Ub7VwLBB0OzZs3L9EIhNlAydSD4HwxWXy+EGyCmEhcBn4jdBcA5EZY7lEuuxCp53qJJdrr3CKxNJiclgb5hKwFASy+qSi2Mp83typASwEUk9a1LU0tBwCA8Z7KuxJk88a2n\/sCGgDUzzXd6q5SQCBq6ztyzP2aGZaQ+PdMOtFgwTxIz\/+D1CYF4VTGHZDTT9Ct6RJuQSbmI6EGCIJRlg8DBNwL2ttqPwbb2jAfltUgdkATGVSRbgHH8QR\/3KullgO9cmCVAQIgIBuPP2V5rwkGBJ1wWz7kszMTaQYRYMy0z1+UTQgYZJZxKZiQzDlLg\/x99ZULKrkuiFnJ8mBJ8DeVcy1sBRgBAotE4EkwyhePnGup5cBUcGCVAIIAAQy15CPw1wQDgi6wJ0DIOuDf0coSi1w3HPH\/zzrrrKRNAOKlJJZDt\/piAnxFacTOAwCRZdaEYy8giSyzNCwzKmup5cBUcGDggaAGAQk7tDoznOA2waAZzRXxFRm2lDPSYKjj2shAG66uDDfmflgLVgdYKfIWXKNvO++8cwJGjltqOTBVHBhoIGiCAC2PsczwTxPfcAAACBlJREFU4cDA+SArBIKIVgmirNuWMDP763OyE71nQOitB4sjWPqRzsriUFeswHmuhuOWWg6sKA4MLBBI07U0h7EsgQABxwgY8PcFBlkGsr6U10RAaXpuQ13e3He+mSRiGRDlnJOEDwFEFoDXXuvr5RWwAPSjLm\/3Ww5MJQcGCghqxknRFYWXFdYEAfV22mmnRAgJpiQRQULl\/ZA8cz6\/QGPzOgkplg+tSLAGtt566yQhCQBFXUuPApRcEIAT5e225cBUc2BggQAjaWBvm9mvCQjstddeST4Ak3644F59TXMfCMgnl4TkTcBuYOAddB8xEQNgNbAwoh2rFhKMrBTIQIvydttyYEVwYKCBoBtDaxCQKkpAu9UbqSxAQH64BCJZicOBAeGXlWglQBYYAGBFcEfkETg3lj6M1L\/2XMuBfjmwSgGBL9eGJTARICD5Bwhoy3Y0MJA1KEgpZsFK4Lq0INDvlG3rTwYHVhogmIiHlxfgTTSCOxYBDEvAC0dcAu8jRHKQlYPRwECikXgEy8D7BWPpw0TwoW2j5UCTA6sUEIgF+KrPWAQwQIA74EtBAoGCjfICvCRkGXA0MHBfyUfeMWgORHvccmBFcmCVAoKxMroGAR8y8YaZb9zx8b0h6KUhryN7+9AHSEayDMbah\/a6lgOTyYEWCHrgrs9WyR6UCuyNRNF+vr5VCT9+4hVWkX+vpdL6cgqkClse7KH5tkrLgRXOgWkBBCucC6N0QCYg3953CXxkwpeMfbzELx\/5AAlT31dufJnGcqGvxfjOvA+fjNJ0e7rlwLTgQAsEXYZBToDvGNqyBKQIyxIMMBALECMg9F5V9t0AloGlQCDgzUXWQpem26KWA9OSAy0QdBkWAUFLgVYGfNMOEPh2oaoBBvH6MQAABjUI1NmDrmmp5cB050ALBF1GSEoyQfexUvGA+MCIdwJ8ojzAwBdspQ1zC8ISaEGgC0PbomnPgUkHgmnPgUYHfYLaEqNfOPLlIKd9M8CXicI9kLYMDHxOzNds5RNwB1oQwK2WVkYOtECwdNT4+9J\/vSTk09ZeBtpzzz2TbwmyDHzQxG8U+CkzHyDZYYcdEjDwY5qAoAWBpYxsNyslB1og6AyboKCvB8n\/F+339WEZiD43Lgkp3ARZhPZ9R8BXbAUSWQSAo9NM+7\/lwErLgRYIOkNn7d97A74rKCYgOUgsAPnoKDdBMNDqAM0vgMgtcNy5vP3fcmCl58C4gGClf\/rqAfxuoQ+IyBnwqzaW\/3yr\/qijjkrcBMuJYgbKvGsgZgAUqiba3ZYDKy0HWiBYOnQCgD5B7kvEfq\/AW4piBBKIvKQEDPxKDRDw9qCVhaWXtpuWAys9B1ogqIbQrwvT8ieccEIi9KwA7xP4JRm\/bXfyyScnbw62IFAxrd0dCA60QDDMMIoB+GgpIFBFgFAMgevguKWWA4PEgWGBYJAecizPcvPNNycfErE0OJbr22taDqxMHGiBYJjR8sOWhx122DBn2+KWA4PFgRYIBms826dpOTAmDrRAMCa2tRe1HBgADlSP0AJBxYyVYdf7Dn4zUQakLyetDH1u+zj9OdACwTjHyDsIPkhy5zvfecSWZCtuscUWqRs5N+LFS08CAV9G8q6D31GU5rz0VAIKfkil2Y+tttoq7brrrkk6dNRtty0HmhxogaDJkT6Pva1IuL2vMNKlvm1w7LHHpm7kXH2tn2tDdZl9v5Egv2G99dZLfpexXtEAJoceemiaOXOmqsto2223LZmR66yzzrKydqflQJMDLRA0OTLKMYGTWUgrI8czZsxIvlfo2JeN\/X4C7V03NWfOnORHULuRc3VdwiyJyY+iNOnoo49O3n1Ye+21k0+k1df5bJpPqNVl9gHIDTfcYLelVYUDfT5nCwR9MmzNNddM3kXwajLaeOONE6G3j5jiXmmWitxn08uq+zQ6cNh9991Tk3wize86Lqvc7rQcmAAOtEDQJxMvvfTSREj9uCp\/3TsK5513XnKM4mtGtLOmuQ1+B6Gp2ZvHCxcuTN50dI00Z2a\/bMYmeRkq2la3pZYDE8GBFgjGwUXfK\/TWot85qJvxOXMpysq8v+A7B7Vm93NnV111VarLgQtLwDUttRyYag60QDAOjgvE8cl9vCSasbRHY\/sNBGX8c1ZErdlzzsnPoNflLACWgGvGQuuuu27yXQWBxLheAFMw072AU5S325WcA5PQ\/RYIxshUbyb6QAkT368dRTN+9Yi7cO2110bRcttNNtkk+UryFVdckfxc2nInx3HgvQgBS6sK0czWW2+dxCouuOCCAjxR3m5bDjQ50AJBkyM9HPP799tvv0TgCd5aa61VrrJWT9B957AUNP7Q0FwE7sQZZ5zROHvr4ZZbbpmsQHQjH0\/xMdVba3ffY63su+++CSB5byK1\/1oOjMCBFghGYE63U5buDj\/88EQYfb7Mtwl22mmnxL8\/\/fTTk1WE2lWINgDEEUcckSQCAQ\/BwTjX3Ppm4uzZs8v6vw+i1OTn1QBK85o4tjx56qmnJp9e9yFWv8+gj3G+3bYc6MaBFgi6cWWEMib4PvvsUz5QcvHFF5eaNO4ee+xRlvrkEDguJ6o\/goeXXXZZ8lsIxxxzTHXmtru+n0ijb7\/99qlJtDygWbx48W0v7JRwA\/zUGgBgUVx++eWd0vb\/SsOBFdTRFgjGwHiBv1rLCvIJ9im\/8soru7aojk+enXPOOV3P91oIBHwt6dxzz+16iYDh8ccfn9zHftdKbWHLgQYHWiBoMKQ9bDmwKnLg\/wEAAP\/\/FAXWYgAAAAZJREFUAwA59ft5Vt+ckAAAAABJRU5ErkJggg==","height":129,"width":258}}
%---
%[output:5030fb10]
%   data: {"dataType":"text","outputData":{"text":"作成した行列サイズ: 34 カテゴリ × 366 日\n","truncated":false}}
%---
%[output:2f44add0]
%   data: {"dataType":"text","outputData":{"text":"\n関連性の高いカテゴリペア:\n","truncated":false}}
%---
%[output:5ba0852b]
%   data: {"dataType":"text","outputData":{"text":" 日記手帳 ←→ 趣味 (相関: 0.934)\n 生活 ←→ 趣味 (相関: 0.853)\n 日記手帳 ←→ 生活 (相関: 0.810)\n","truncated":false}}
%---
%[output:56f9e58c]
%   data: {"dataType":"text","outputData":{"text":"\n【TOP10データの検証】\n","truncated":false}}
%---
%[output:40aa3780]
%   data: {"dataType":"text","outputData":{"text":"  TOP10カテゴリ数: 10\n","truncated":false}}
%---
%[output:37b96a32]
%   data: {"dataType":"text","outputData":{"text":"  TOP10販売行列サイズ: 10 × 366\n","truncated":false}}
%---
%[output:42347582]
%   data: {"dataType":"text","outputData":{"text":"  各カテゴリの総販売数:\n","truncated":false}}
%---
%[output:9508a64c]
%   data: {"dataType":"text","outputData":{"text":"    1. コミック: 1383186冊\n    2. 月刊誌: 856595冊\n    3. 文庫: 630459冊\n    4. 児童: 325607冊\n    5. 週刊誌: 199600冊\n    6. 趣味: 180914冊\n    7. 生活: 137308冊\n    8. 文芸: 111247冊\n    9. 地図・ガイド: 104020冊\n    10. ビジネス: 99534冊\n","truncated":false}}
%---
%[output:1316368d]
%   data: {"dataType":"text","outputData":{"text":"\n結果を step1_results.mat に保存しました\n","truncated":false}}
%---
%[output:3e92dcb2]
%   data: {"dataType":"text","outputData":{"text":"  - 全カテゴリ数: 34\n","truncated":false}}
%---
%[output:02546be7]
%   data: {"dataType":"text","outputData":{"text":"  - TOP10カテゴリ数: 10\n","truncated":false}}
%---
