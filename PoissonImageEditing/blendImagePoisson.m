function imret = blendImagePoisson(im1, im2, roi, targetPosition)

% input: im1 (background), im2 (foreground), roi (in im2), targetPosition (in im1)

%% compute blended image
H_index_source = ceil(min(roi(:,2)));
W_index_source = ceil(min(roi(:,1)));                           %裁剪后坐标偏移量
H_index_target = ceil(min(targetPosition(:,2)));
W_index_target = ceil(min(targetPosition(:,1)));

H_source = ceil( max(roi(:,2)) - H_index_source );                     % 裁剪后的height
W_source = ceil( max(roi(:,1)) - W_index_source );                     % 裁剪后的width
mask = poly2mask( roi(:,1) - W_index_source, roi(:,2) - H_index_source, H_source, W_source);  %区域内的点为1，否则为0
mask = int32(mask);         %转换为int数组

mask(:,1)=0;
mask(:,end)=0;
mask(1,:)=0;
mask(end,:)=0;              %边界处赋0，防止下标出界

counter = 0;
for x=1:H_source
    for y=1:W_source
        if mask(x,y)==1 
            counter=counter+1;
            mask(x,y)=counter;  %按行标号
        end
    end
end

%% 稀疏矩阵A的构造
persistent roi_old A dA
if isempty(roi_old) || size(roi_old,1)~=size(roi,1) || norm(roi_old-roi,2)>1
    roi_old = roi;
    
    tic         %开始计时
    
    row_index = zeros(counter*5,1);
    column_index = zeros(counter*5,1);
    value = zeros(counter*5,1);         %记录稀疏矩阵A的行索引，列索引，非零元素
    
    counter = 0;    %记录第几个Possion方程，也是矩阵的列指标
    index = 0;      %用于记录稀疏矩阵A的指标
    for x=1:H_source
        for y=1:W_source
            if mask(x,y)~=0                 %该点在选定的范围内
                counter=counter+1;
                index = index+1;
                column_index(index) = counter;
                row_index(index) = counter;
                value(index) = 4;
                %A(counter,counter)=4;       %对角元为4
                if mask(x-1,y)~=0           %左边的点在边界内
                    index = index+1;
                    column_index(index) = counter;
                    row_index(index) = mask(x-1,y);
                    value(index) = -1;
                    %A(counter,mask(x-1,y)) = -1;
                end
                
                if mask(x+1,y)~=0           %右边的点在边界内
                    index = index+1;
                    column_index(index) = counter;
                    row_index(index) = mask(x+1,y);
                    value(index) = -1;
                    %A(counter,mask(x+1,y)) = -1;
                end
                
                if mask(x,y-1)~=0           %上边的点在边界内
                    index = index+1;
                    column_index(index) = counter;
                    row_index(index) = mask(x,y-1);
                    value(index) = -1;
                    %A(counter,mask(x,y-1)) = -1;
                end
                
                if mask(x,y+1)~=0           %下边的点在边界内
                    index = index+1;
                    column_index(index) = counter;
                    row_index(index) = mask(x,y+1);
                    value(index) = -1;
                    %A(counter,mask(x,y+1)) = -1;
                end
            end
        end
    end
    row_index(index+1:end)=[];
    column_index(index+1:end)=[];
    value(index+1:end)=[];
    
    A = sparse(row_index, column_index, value);      %稀疏矩阵创建
    dA = decomposition(A);
    disp('calculate Matrix A');
    toc         %计时结束
end

%% 梯度矩阵B的赋值
B = zeros(counter,3);             %梯度矩阵B创建 3代表三维RGB空间
tic

counter = 0;
for x=1:H_source
    for y=1:W_source
        if mask(x,y)~=0                 %该点在选定的范围内
            counter=counter+1;
            if mask(x-1,y)~=0           %左边的点在边界内
                B(counter,:) = B(counter,:)+ reshape(double(im2( H_index_source + x, W_index_source + y, :))-double(im2( H_index_source + x-1, W_index_source + y, :)),[1,3]); 
            else
                B(counter,:) = B(counter,:)+ double( reshape( im1( H_index_target + x-1, W_index_target + y, :),[1,3]));
            end
            
            if mask(x+1,y)~=0           %右边的点在边界内
                 B(counter,:) = B(counter,:)+ reshape(double(im2( H_index_source + x, W_index_source + y, :))-double(im2( H_index_source + x+1, W_index_source + y, :)),[1,3]);
            else
                B(counter,:) = B(counter,:)+ double( reshape( im1( H_index_target + x+1, W_index_target + y, :),[1,3]));
            end
            
            if mask(x,y-1)~=0           %上边的点在边界内
                 B(counter,:) = B(counter,:)+ reshape(double(im2( H_index_source + x, W_index_source + y, :))-double(im2( H_index_source + x, W_index_source + y-1, :)),[1,3]);
            else
                B(counter,:) = B(counter,:)+ double( reshape( im1( H_index_target + x, W_index_target + y-1, :),[1,3]));
            end
            
            if mask(x,y+1)~=0           %下边的点在边界内
                 B(counter,:) = B(counter,:)+ reshape(double(im2( H_index_source + x, W_index_source + y, :))-double(im2( H_index_source + x, W_index_source + y+1, :)),[1,3]);
            else
                B(counter,:) = B(counter,:)+ double( reshape( im1( H_index_target + x, W_index_target + y+1, :),[1,3]));
            end
        end
    end
end
disp('calculate Matrix B');
toc

%% 计算得到新图像
target_Image = dA\B;

imret = im1;
counter = 0;
for x=1:H_source
    for y=1:W_source
        if mask(x,y)~=0                 %该点在选定的范围内
            counter=counter+1;
            imret(x+H_index_target, y+W_index_target, :) = target_Image(counter,:);
        end
    end
end

%imwrite(imret,'result.jpg');       %输出图像
