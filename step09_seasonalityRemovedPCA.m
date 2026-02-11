%% 季節性除去後のPCA・クラスタリング分析
% 目的: 月・曜日ダミーで季節成分を除去した残差の相関行列でPCAを実施し、
%       季節性を除いた「真の共変動」に基づくカテゴリ配置候補を可視化する

%% 1. データ読み込み（既存コードで読み込み済みの前提）
% salesMatrix: 366日 × 34カテゴリ の全店舗合算販売冊数
% categoryNames: 34カテゴリ名のセル配列
% dateVec: 366日分の日付ベクトル (datetime)

%% 2. 季節性ダミー変数の構築
monthDummy = dummyvar(month(dateVec));   % 366×12
monthDummy(:,12) = [];                    % 基準月を除外 → 366×11

dowDummy = dummyvar(weekday(dateVec));    % 366×7
dowDummy(:,7) = [];                       % 基準曜日を除外 → 366×6

X_seasonal = [monthDummy, dowDummy];      % 366×17

%% 3. 各カテゴリの残差を計算
nDays = size(salesMatrix, 1);
nCats = size(salesMatrix, 2);
residualMatrix = zeros(nDays, nCats);

for c = 1:nCats
    y = salesMatrix(:, c);
    beta = [ones(nDays,1), X_seasonal] \ y;   % OLS
    yHat = [ones(nDays,1), X_seasonal] * beta;
    residualMatrix(:, c) = y - yHat;
end

%% 4. 残差の相関行列
R_resid = corrcoef(residualMatrix);

%% 5. PCA（残差ベース）
[coeff, score, latent] = pca(R_resid);
explained = latent / sum(latent) * 100;
cumExplained = cumsum(explained);

fprintf('残差PCA: PC1=%.1f%%, PC2=%.1f%%, 累積=%.1f%%\n', ...
    explained(1), explained(2), cumExplained(2));

%% 6. クラスタリング（Ward法）
distMatrix = (1 - R_resid) / 2;              % 相関→距離変換
distVec = squareform(distMatrix, 'tovector');  % 圧縮距離ベクトル
Z = linkage(distVec, 'ward');

% シルエット分析で最適クラスタ数を選定
silScores = zeros(8, 1);
for k = 2:8
    clusterIdx = cluster(Z, 'maxclust', k);
    silScores(k) = mean(silhouette(score(:,1:2), clusterIdx));
end
[~, bestK] = max(silScores);
fprintf('最適クラスタ数: %d (シルエット=%.3f)\n', bestK, silScores(bestK));

clusterIdx = cluster(Z, 'maxclust', bestK);

%% 7. 可視化: Before/After 比較
figure('Position', [100 100 1400 600]);
colors = lines(max(bestK, 5));

% --- 左: 元データのPCA（比較用） ---
subplot(1,2,1);
R_raw = corrcoef(salesMatrix);
[~, scoreRaw] = pca(R_raw);
clusterRaw = cluster(linkage(squareform((1-R_raw)/2,'tovector'),'ward'), 'maxclust', 5);

gscatter(scoreRaw(:,1), scoreRaw(:,2), clusterRaw, colors(1:5,:), '.', 20);
hold on;
for c = 1:nCats
    text(scoreRaw(c,1)+0.02, scoreRaw(c,2), categoryNames{c}, 'FontSize', 7);
end
hold off;
title('元データ（季節性あり）');
xlabel('PC1'); ylabel('PC2');
legend('off'); grid on;

% --- 右: 残差のPCA ---
subplot(1,2,2);
gscatter(score(:,1), score(:,2), clusterIdx, colors(1:bestK,:), '.', 20);
hold on;
for c = 1:nCats
    text(score(c,1)+0.02, score(c,2), categoryNames{c}, 'FontSize', 7);
end
hold off;
title('季節性除去後（残差ベース）');
xlabel('PC1'); ylabel('PC2');
legend('off'); grid on;

sgtitle('PCAによるカテゴリ配置マップ: 季節性除去の影響', 'FontSize', 14);

%% 8. 残差ベースのクラスタ内平均相関を確認
fprintf('\n=== 残差ベース クラスタ別 平均相関 ===\n');
for k = 1:bestK
    members = find(clusterIdx == k);
    if length(members) < 2
        fprintf('クラスタ%d: %s（単独）\n', k, categoryNames{members});
        continue;
    end
    subR = R_resid(members, members);
    upperTriIdx = triu(true(size(subR)), 1);
    meanCorr = mean(subR(upperTriIdx));
    fprintf('クラスタ%d (平均r=%.3f): %s\n', k, meanCorr, ...
        strjoin(categoryNames(members), ', '));
end

%% 9. 「中程度だがクラスタを形成」するペアの抽出
fprintf('\n=== 残差ベース: r=0.3〜0.5 の中程度相関ペア ===\n');
for i = 1:nCats-1
    for j = i+1:nCats
        r = R_resid(i,j);
        if r >= 0.3 && r < 0.5
            % 同一クラスタ内かどうか
            sameCluster = (clusterIdx(i) == clusterIdx(j));
            marker = '';
            if sameCluster
                marker = ' ★同一クラスタ → 配置候補';
            end
            fprintf('  %s ↔ %s: r=%.3f%s\n', ...
                categoryNames{i}, categoryNames{j}, r, marker);
        end
    end
end